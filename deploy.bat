@echo off
REM ==============================================================================
REM Deploy to GitHub Script
REM Repository: https://github.com/Athoillah21/Healthcheck-Report-Liquid-Glass-Style
REM ==============================================================================

set REPO_URL=https://github.com/Athoillah21/Healthcheck-Report-Liquid-Glass-Style.git

echo ========================================
echo   GitHub Deployment Script
echo ========================================
echo.

REM Check if git is installed
where git >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [ERROR] Git is not installed or not in PATH!
    pause
    exit /b 1
)

REM Check if .git folder exists
if not exist ".git" (
    echo [INFO] Initializing Git repository...
    git init
    
    echo [INFO] Adding remote origin...
    git remote add origin %REPO_URL%
) else (
    echo [INFO] Git repository already initialized.
    git remote set-url origin %REPO_URL% 2>nul || git remote add origin %REPO_URL%
)

REM Create .gitignore if not exists
if not exist ".gitignore" (
    echo [INFO] Creating .gitignore...
    (
        echo # Output reports
        echo *.html
        echo report/
        echo.
        echo # Logs
        echo *.log
        echo.
        echo # Sensitive files
        echo .pgpass
        echo *.env
        echo.
        echo # OS files
        echo .DS_Store
        echo Thumbs.db
    ) > .gitignore
)

echo.
echo [STEP 1] Staging all files...
git add .

echo.
echo [STEP 2] Committing changes...
for /f "tokens=1-3 delims=/ " %%a in ('date /t') do set DATE=%%c-%%a-%%b
for /f "tokens=1-2 delims=: " %%a in ('time /t') do set TIME=%%a:%%b
git commit -m "Update PostgreSQL Healthcheck Report Script - %DATE% %TIME%"

echo.
echo [STEP 3] Pushing to GitHub...
echo [INFO] Repository: %REPO_URL%

git branch -M main
git push -u origin main

if %ERRORLEVEL% neq 0 (
    echo [WARN] Push to 'main' failed, trying 'master'...
    git branch -M master
    git push -u origin master
)

echo.
if %ERRORLEVEL% equ 0 (
    echo ========================================
    echo   Deployment Successful!
    echo ========================================
    echo.
    echo View your repository at:
    echo https://github.com/Athoillah21/Healthcheck-Report-Liquid-Glass-Style
) else (
    echo ========================================
    echo   Deployment Failed!
    echo ========================================
    echo.
    echo Please check:
    echo   1. You have push access to the repository
    echo   2. You are authenticated with GitHub
    echo   3. The repository exists on GitHub
)

echo.
pause
