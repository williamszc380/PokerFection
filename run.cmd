@echo off
rem run [--profile=N] [flutter run options]: see tool\run.dart.
setlocal
set "root=%FLUTTER_ROOT%"
if not defined root set "root=%USERPROFILE%\dev\flutter"
set "PATH=%root%\bin;%PATH%"
dart run "%~dp0tool\run.dart" %*
