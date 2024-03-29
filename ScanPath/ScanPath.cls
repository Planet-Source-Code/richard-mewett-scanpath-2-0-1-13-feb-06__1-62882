VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
  Persistable = 0  'NotPersistable
  DataBindingBehavior = 0  'vbNone
  DataSourceBehavior  = 0  'vbNone
  MTSTransactionMode  = 0  'NotAnMTSObject
END
Attribute VB_Name = "cScanPath"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
Option Explicit

'##############################################################################################
'Purpose:       Scan a specified path for files/folders matching the Filter Criteria
'Author:        Richard Mewett ©2003
'Version:       2.0.1 (11th Feb 2006)
'Dependencies:  None!

'This allows filtered scan operations since you can define Min/Max file sizes, Date Ranges
'multiple File Extensions & File Attributes

'Copyright ©2005 Richard Mewett. All rights reserved.
'
'This software is provided "as-is," without any express or implied warranty.
'In no event shall the author be held liable for any damages arising from the
'use of this software.
'If you do not agree with these terms, do not use this code. Use of
'the code implicitly means you have agreed to these terms.
'
'Permission is granted to anyone to use this software for any purpose,
'including commercial use, and to alter and redistribute it, provided that
'the following conditions are met:
'
'1. All redistributions of source code files must retain all copyright
'   notices that are currently in place, and this list of conditions without
'   any modification.
'
'2. All redistributions in binary form must retain all occurrences of the
'   above copyright notice and web site addresses that are currently in
'   place (for example, in the About boxes).
'
'3. Modified versions in source or binary form must be plainly marked as
'   such, and must not be misrepresented as being the original software.

'History (dd/mm/yy):
'14/10/05   Added Pattern Matching to Extensions Filter
'11/02/06   Fixed resource leak in DirectScan (thanks Philip Ciebiera!)
'           Added ExtendedDetail Mode - this is designed as a simpler -
'           alternative to the WFDPointer() function
'##############################################################################################

Private Declare Function FindFirstFile Lib "kernel32" Alias "FindFirstFileA" (ByVal lpFileName As String, lpFindFileData As WIN32_FIND_DATA) As Long
Private Declare Function FindNextFile Lib "kernel32" Alias "FindNextFileA" (ByVal hFindFile As Long, lpFindFileData As WIN32_FIND_DATA) As Long
Private Declare Function FindClose Lib "kernel32" (ByVal hFindFile As Long) As Long
Private Declare Function FileTimeToSystemTime Lib "kernel32" (lpFileTime As FILETIME, lpSystemTime As SYSTEMTIME) As Long

Private Const MAX_PATH As Long = 260
Private Const INVALID_HANDLE_VALUE As Long = -1

Private Const FILE_ATTRIBUTE_ARCHIVE As Long = &H20
Private Const FILE_ATTRIBUTE_COMPRESSED As Long = &H800
Private Const FILE_ATTRIBUTE_DIRECTORY As Long = &H10
Private Const FILE_ATTRIBUTE_HIDDEN As Long = &H2
Private Const FILE_ATTRIBUTE_NORMAL As Long = &H80
Private Const FILE_ATTRIBUTE_READONLY As Long = &H1
Private Const FILE_ATTRIBUTE_SYSTEM As Long = &H4
Private Const FILE_ATTRIBUTE_TEMPORARY As Long = &H100

Private Const NULL_CHAR As Long = 0
Private Const EXT_SEPERATOR_CHAR As String = "."
Private Const MASK_SEPERATOR_CHAR As String = ";"

Private Const ALL_FILES As String = "*.*"
Private Const PARENT_DIR As String = "."
Private Const ROOT_DIR As String = ".."

Private Const DIR_KEY As String = "1"
Private Const FILE_KEY As String = "0"

Private Type SYSTEMTIME
    wYear             As Integer
    wMonth            As Integer
    wDayOfWeek        As Integer
    wDay              As Integer
    wHour             As Integer
    wMinute           As Integer
    wSecond           As Integer
    wMilliseconds     As Integer
End Type

Private Type FILETIME
    dwLowDateTime     As Long
    dwHighDateTime    As Long
End Type

Private Type WIN32_FIND_DATA
    dwFileAttributes  As Long
    ftCreationTime    As FILETIME
    ftLastAccessTime  As FILETIME
    ftLastWriteTime   As FILETIME
    nFileSizeHigh     As Long
    nFileSizeLow      As Long
    dwReserved0       As Long
    dwReserved1       As Long
    cFileName         As String * MAX_PATH
    cAlternate        As String * 14
End Type

Public Enum DateTypeEnum
    Modified = 0
    Created = 1
    LastAccessed = 2
End Enum

Private mWFD As WIN32_FIND_DATA

Private mFromDate As Date
Private mToDate As Date
Private mMaximumSize As Long
Private mMinimumSize As Long

Private mArchive As Boolean
Private mCompressed As Boolean
Private mFolder As Boolean
Private mHidden As Boolean
Private mNormal As Boolean
Private mReadOnly As Boolean
Private mSystem As Boolean
Private mFilter As String

Private mDirCount As Long
Private mFileCount As Long
Private mDateType As DateTypeEnum
Private mDateCheck As Integer
Private mSizeCheck As Integer
Private mCancelScan As Boolean
Private mExtendedDetail As Boolean
Private mPatternMatching As Boolean
Private mSorted As Boolean
Private mFilters() As String

Public Event DirMatch(Directory As String, Path As String)
Public Event FileMatch(Filename As String, Path As String)

Public Event DirMatchEx(Directory As String, Path As String, Attributes As Long, LastWriteTime As Date, CreationTime As Date, LastAccessTime As Date)
Public Event FileMatchEx(Filename As String, Path As String, FileSize As Long, Attributes As Long, LastWriteTime As Date, CreationTime As Date, LastAccessTime As Date)


Public Property Get Archive() As Boolean
    Archive = mArchive
End Property

Public Property Let Archive(ByVal bNewValue As Boolean)
    mArchive = bNewValue
End Property

Private Sub Class_Initialize()
    mArchive = True
    mCompressed = True
    mFolder = True
    mNormal = True
    mReadOnly = True
End Sub

Public Property Get Compressed() As Boolean
    Compressed = mCompressed
End Property

Public Property Let Compressed(ByVal bNewValue As Boolean)
    mCompressed = bNewValue
End Property

Public Property Get DateType() As DateTypeEnum
    DateType = mDateType
End Property

Public Property Let DateType(ByVal vNewValue As DateTypeEnum)
    mDateType = vNewValue
End Property

Public Property Get DirCount() As Long
    DirCount = mDirCount
End Property

Private Function DirectScan(Path As String, SubFolders As Boolean) As Long
    '##############################################################################################
    'This scans a path (and optionally subfolders) for all files that match
    'the Filter
    
    Dim colDirs As Collection
    Dim lCount As Long
    Dim hFile As Long
    Dim bOK As Boolean
    Dim sDir As String
    Dim sFile As String
    
    Set colDirs = New Collection
    
    colDirs.Add Path
    Do While colDirs.Count And Not mCancelScan
        sDir = colDirs.Item(1)
        colDirs.Remove 1
        
        hFile = FindFirstFile(sDir & ALL_FILES, mWFD)
        If hFile = INVALID_HANDLE_VALUE Then
            Exit Do
        End If
        
        Do
            sFile = Left$(mWFD.cFileName, InStr(mWFD.cFileName, Chr$(NULL_CHAR)) - 1)
            Select Case sFile
            Case ROOT_DIR, PARENT_DIR
            
            Case Else
                bOK = FileMatches(mWFD)
                
                If (mWFD.dwFileAttributes And FILE_ATTRIBUTE_DIRECTORY) Then
                    If bOK Then
                        If SubFolders Then
                            colDirs.Add sDir & sFile & "\"
                        End If
                    
                        mDirCount = mDirCount + 1
                        
                        If mExtendedDetail Then
                            With mWFD
                                RaiseEvent DirMatchEx(sFile, sDir, .dwFileAttributes, FormatFileDate(.ftLastWriteTime), FormatFileDate(.ftCreationTime), FormatFileDate(.ftLastAccessTime))
                            End With
                        Else
                            RaiseEvent DirMatch(sFile, sDir)
                        End If
                    End If
                Else
                    If bOK Then
                        mFileCount = mFileCount + 1
                        
                        If mExtendedDetail Then
                            With mWFD
                                RaiseEvent FileMatchEx(sFile, sDir, .nFileSizeLow, .dwFileAttributes, FormatFileDate(.ftLastWriteTime), FormatFileDate(.ftCreationTime), FormatFileDate(.ftLastAccessTime))
                            End With
                        Else
                            RaiseEvent FileMatch(sFile, sDir)
                        End If
                    End If
                End If
                
            End Select
            
            lCount = lCount + 1
            If (lCount Mod 10) = 0 Then
                DoEvents
                If mCancelScan Then
                    Exit Do
                End If
            End If
        Loop While FindNextFile(hFile, mWFD)
        
        FindClose hFile
    Loop
    
    Set colDirs = Nothing
End Function

Public Property Get FileCount() As Long
    FileCount = mFileCount
End Property

Private Function FileMatches(udtWFD As WIN32_FIND_DATA) As Boolean
    '##############################################################################################
    'Purpose: Used to verify a file matches the Filter Criteria
    '##############################################################################################
    
    Dim dtFileDate As Date
    Dim nFilter As Integer
    Dim nPos As Integer
    Dim bFolder As Boolean
    Dim bOK As Boolean
    Dim sExt As String
    
    bFolder = (udtWFD.dwFileAttributes And FILE_ATTRIBUTE_DIRECTORY)
    
    If bFolder Or (mFilter = ALL_FILES) Then
        bOK = True
    Else
        '##############################################################################################
        'Test Extension against Filter:
        'Remove the padding from filename by truncating at first null char
        sExt = UCase$(Mid$(udtWFD.cFileName, 1, InStr(udtWFD.cFileName, Chr$(NULL_CHAR)) - 1))
        
        If mPatternMatching Then
            'Complex searches such as *test??.text
            For nFilter = LBound(mFilters) To UBound(mFilters)
                If sExt Like mFilters(nFilter) Then
                    bOK = True
                    Exit For
                End If
            Next nFilter
        Else
            'Simple extension only search
            'Get the Extension - Scan backwards since Windows uses the last "." to determine extension
            '>> i.e. datafile.txt.bmp is a bmp file not a txt file
            nPos = InStrRev(sExt, EXT_SEPERATOR_CHAR)
            If nPos > 0 Then
                'Append seperator char to Extension prevent false matches
                '>> i.e. *.rtf should not match a file with a .r extension
                'Looping through an array of Filters would negate the need for this but Instr is faster
                sExt = UCase$(Mid$(sExt, nPos + 1)) & MASK_SEPERATOR_CHAR
                bOK = (InStr(mFilter, sExt) > 0)
            End If
        End If
    End If
    
    If bOK Then
        '##############################################################################################
        'Test Attributes against Filter
        If (udtWFD.dwFileAttributes And FILE_ATTRIBUTE_ARCHIVE) Then
            bOK = mArchive
        End If
        If (udtWFD.dwFileAttributes And FILE_ATTRIBUTE_COMPRESSED) Then
            bOK = bOK And mCompressed
        End If
        If (udtWFD.dwFileAttributes And FILE_ATTRIBUTE_DIRECTORY) Then
            bOK = bOK And mFolder
        End If
        If (udtWFD.dwFileAttributes And FILE_ATTRIBUTE_HIDDEN) Then
            bOK = bOK And mHidden
        End If
        If (udtWFD.dwFileAttributes And FILE_ATTRIBUTE_NORMAL) Then
            bOK = bOK And mNormal
        End If
        If (udtWFD.dwFileAttributes And FILE_ATTRIBUTE_READONLY) Then
            bOK = bOK And mReadOnly
        End If
        If (udtWFD.dwFileAttributes And FILE_ATTRIBUTE_SYSTEM) Then
            bOK = bOK And mSystem
        End If
    End If
        
    If bOK And Not bFolder Then
        '##############################################################################################
        'Test Size against Filter
        Select Case mSizeCheck
        Case 1
            bOK = (udtWFD.nFileSizeLow >= mMinimumSize)
        Case 2
            bOK = (udtWFD.nFileSizeLow <= mMaximumSize)
        Case 3
            bOK = (udtWFD.nFileSizeLow >= mMinimumSize) And (udtWFD.nFileSizeLow <= mMaximumSize)
        End Select
                
        If bOK And (mDateCheck > 0) Then
            '##############################################################################################
            'Test Date against Filter
            Select Case mDateType
            Case 0
                dtFileDate = FormatFileDate(udtWFD.ftLastWriteTime)
            Case 1
                dtFileDate = FormatFileDate(udtWFD.ftCreationTime)
            Case 2
                dtFileDate = FormatFileDate(udtWFD.ftLastAccessTime)
            End Select
            
            Select Case mDateCheck
            Case 1
                bOK = (dtFileDate >= mFromDate)
            Case 2
                bOK = (dtFileDate <= mToDate)
            Case 3
                bOK = (dtFileDate >= mFromDate) And (dtFileDate <= mToDate)
            End Select
        End If
    End If
                    
    FileMatches = bOK
End Function

Public Property Get Filter() As String
    If Right$(mFilter, 1) = MASK_SEPERATOR_CHAR Then
        Filter = Left$(mFilter, Len(mFilter) - 1)
    Else
        Filter = mFilter
    End If
End Property

Public Property Let Filter(ByVal sNewValue As String)
    mFilter = Trim$(sNewValue)
End Property

Public Property Get Folder() As Boolean
    Folder = mFolder
End Property

Public Property Let Folder(ByVal bNewValue As Boolean)
    mFolder = bNewValue
End Property

Private Function FormatFileDate(CT As FILETIME) As String
    '##############################################################################################
    'Converts Windows Internal File Dates into standard text format

    Const SHORT_DATE = "Short Date"
    Const SHORT_TIME = "Short Time"
    
    Dim ST As SYSTEMTIME
    Dim ds(1) As Single
       
    If FileTimeToSystemTime(CT, ST) Then
        ds(0) = DateSerial(ST.wYear, ST.wMonth, ST.wDay)
        ds(1) = TimeSerial(ST.wHour, ST.wMinute, ST.wSecond)
        
        FormatFileDate = Format$(ds(0), SHORT_DATE) & " " & Format$(ds(1), SHORT_TIME)
    End If
End Function

Public Property Get FromDate() As Date
    FromDate = mFromDate
End Property

Public Property Let FromDate(ByVal vNewValue As Date)
    mFromDate = vNewValue
End Property

Public Property Get Hidden() As Boolean
    Hidden = mHidden
End Property

Public Property Let Hidden(ByVal bNewValue As Boolean)
    mHidden = bNewValue
End Property

Public Property Get MaximumSize() As Long
    MaximumSize = mMaximumSize
End Property

Public Property Let MaximumSize(ByVal vNewValue As Long)
    mMaximumSize = vNewValue
End Property

Public Property Get MinimumSize() As Long
    MinimumSize = mMinimumSize
End Property

Public Property Let MinimumSize(ByVal vNewValue As Long)
    mMinimumSize = vNewValue
End Property

Public Property Get Normal() As Boolean
    Normal = mNormal
End Property

Public Property Let Normal(ByVal bNewValue As Boolean)
    mNormal = bNewValue
End Property

Public Property Get ReadOnly() As Boolean
    ReadOnly = mReadOnly
End Property

Public Property Let ReadOnly(ByVal bNewValue As Boolean)
    mReadOnly = bNewValue
End Property

Private Function SortedScan(Path As String, SubFolders As Boolean)
    '##############################################################################################
    'This scans a path (and optionally subfolders) for all files that match
    'the Filter. The difference between this and DirectScan is that it sorts
    'the files before raising Events - it is therefore slower than DirectScan
    
    Dim lCount As Long
    Dim hFile As Long
    Dim nCount As Integer
    Dim nFile As Integer
    Dim bOK As Boolean
    Dim sFile As String
    Dim sFiles() As String
    
    If mCancelScan Then
        Exit Function
    End If
    
    ReDim sFiles(1 To 10)
    
    hFile = FindFirstFile(Path & ALL_FILES, mWFD)
    If hFile <> INVALID_HANDLE_VALUE Then
        Do
            sFile = Left$(mWFD.cFileName, InStr(mWFD.cFileName, Chr$(NULL_CHAR)) - 1)
            
            Select Case sFile
            Case ROOT_DIR, PARENT_DIR
            
            Case Else
                bOK = FileMatches(mWFD)
                
                If bOK Then
                    nFile = nFile + 1
                    If nFile > UBound(sFiles) Then
                        ReDim Preserve sFiles(1 To nFile + 10)
                    End If
                    
                    If (mWFD.dwFileAttributes And FILE_ATTRIBUTE_DIRECTORY) Then
                        sFiles(nFile) = DIR_KEY & sFile
                    Else
                        sFiles(nFile) = FILE_KEY & sFile
                    End If
                End If
            
            End Select
            
            lCount = lCount + 1
            If (lCount Mod 10) = 0 Then
                DoEvents
                If mCancelScan Then
                    Exit Do
                End If
            End If
        Loop While FindNextFile(hFile, mWFD)
        
        FindClose (hFile)
    End If
    
    If nFile > 0 Then
        SortStrings sFiles(), 1, nFile
        
        For nCount = 1 To nFile
            If Mid$(sFiles(nCount), 1, 1) = DIR_KEY Then
                If mExtendedDetail Then
                    hFile = FindFirstFile(Path & Mid$(sFiles(nCount), 2), mWFD)
                    With mWFD
                        RaiseEvent DirMatchEx(Mid$(sFiles(nCount), 2), Path, .dwFileAttributes, FormatFileDate(.ftLastWriteTime), FormatFileDate(.ftCreationTime), FormatFileDate(.ftLastAccessTime))
                    End With
                    FindClose (hFile)
                Else
                    RaiseEvent DirMatch(Mid$(sFiles(nCount), 2), Path)
                End If
            
                If SubFolders Then
                    mDirCount = mDirCount + 1
                    SortedScan Path & Mid$(sFiles(nCount), 2) & "\", SubFolders
                End If
            Else
                mFileCount = mFileCount + 1
                
                If mExtendedDetail Then
                    hFile = FindFirstFile(Path & Mid$(sFiles(nCount), 2), mWFD)
                    With mWFD
                        RaiseEvent FileMatchEx(Mid$(sFiles(nCount), 2), Path, .nFileSizeLow, .dwFileAttributes, FormatFileDate(.ftLastWriteTime), FormatFileDate(.ftCreationTime), FormatFileDate(.ftLastAccessTime))
                    End With
                    FindClose (hFile)
                Else
                    RaiseEvent FileMatch(Mid$(sFiles(nCount), 2), Path)
                End If
            End If
            
            If mCancelScan Then
                Exit For
            End If
        Next nCount
    End If
End Function

Private Sub SortStrings(sArray() As String, ByVal nFirst As Integer, ByVal nLast As Integer)
    Dim nBoundary As Integer
    Dim nIndex As Integer

    If nLast <= nFirst Then Exit Sub

    SwapS sArray(nFirst), sArray((nFirst + nLast) / 2)
    
    nBoundary = nFirst

    For nIndex = nFirst + 1 To nLast
        If StrComp(sArray(nFirst), sArray(nIndex), vbTextCompare) = 1 Then
            nBoundary = nBoundary + 1
            SwapS sArray(nBoundary), sArray(nIndex)
        End If
    Next nIndex

    SwapS sArray(nFirst), sArray(nBoundary)

    SortStrings sArray(), nFirst, nBoundary - 1
    SortStrings sArray(), nBoundary + 1, nLast
End Sub

Public Sub StartScan(Path As String, Optional SubFolders As Boolean, Optional Sorted As Boolean, Optional PatternMatching As Boolean, Optional ExtendedDetail As Boolean)
    If Right$(Path, 1) <> "\" Then
        Path = Path & "\"
    End If
    
    mDirCount = 0
    mFileCount = 0
    mPatternMatching = PatternMatching
    mExtendedDetail = ExtendedDetail
    mSorted = Sorted
    
    'Verify a filter (file mask) has been specified
    If Len(mFilter) = 0 Then
        ReDim mFilters(0)
        mFilter = ALL_FILES
    ElseIf mFilter <> ALL_FILES Then
        'Append trailing seperator char to Filter (see FileMatches for details)
        mFilter = UCase$(mFilter) & MASK_SEPERATOR_CHAR
        mFilters() = Split(Left$(mFilter, Len(mFilter) - 1), MASK_SEPERATOR_CHAR)
    End If
    
    If (mMinimumSize > 0) And (mMaximumSize > 0) Then
        mSizeCheck = 3
    ElseIf (mMaximumSize > 0) Then
        mSizeCheck = 2
    ElseIf (mMinimumSize > 0) Then
        mSizeCheck = 1
    Else
        mSizeCheck = 0
    End If
    
    If (CDbl(mFromDate) > 0) And (CDbl(mToDate) > 0) Then
        mDateCheck = 3
    ElseIf (CDbl(mToDate) > 0) Then
        mDateCheck = 2
    ElseIf (CDbl(mFromDate) > 0) Then
        mDateCheck = 1
    Else
        mDateCheck = 0
    End If
    
    mCancelScan = False
    
    If Sorted Then
        SortedScan Path, SubFolders
    Else
        DirectScan Path, SubFolders
    End If
End Sub

Public Sub StopScan()
    mCancelScan = True
End Sub

Private Sub SwapS(Str1 As String, Str2 As String)
    Dim sTemp As String
    
    sTemp = Str1
    Str1 = Str2
    Str2 = sTemp
End Sub

Public Property Get System() As Boolean
    System = mSystem
End Property

Public Property Let System(ByVal bNewValue As Boolean)
    mSystem = bNewValue
End Property

Public Property Get ToDate() As Date
    ToDate = mToDate
End Property

Public Property Let ToDate(ByVal vNewValue As Date)
    mToDate = vNewValue
End Property

Public Function WFDPointer() As Long
    'This returns a pointer to the current dir/file found and
    'may be used to extract extra details (size, dates etc)
    'without the performancec hit of processing the file again
    
    'NOTE: This only works for DirectScan. SortedScan raises events
    'after sorting the results so the mWFD variable is no longer valid
    
    WFDPointer = VarPtr(mWFD)
End Function

