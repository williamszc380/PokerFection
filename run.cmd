@echo off
rem run [--profile=N] [flutter run options]; run -h for help: see tool\run.dart.
setlocal
set "root=%FLUTTER_ROOT%"
if not defined root set "root=%USERPROFILE%\dev\flutter"
set "PATH=%root%\bin;%PATH%"
dart "%~dp0tool\run.dart" %*
