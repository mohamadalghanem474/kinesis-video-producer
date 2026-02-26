#!/bin/bash
set -e

# ANSI escape codes for formatting
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
UNDERLINE="\033[4m"
BLINK="\033[5m"
REVERSE="\033[7m"
HIDDEN="\033[8m"

# Regular Colors
BLACK="\033[0;30m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
PURPLE="\033[0;35m"
CYAN="\033[0;36m"
WHITE="\033[0;37m"

# Bold Colors
BBLACK="\033[1;30m"
BRED="\033[1;31m"
BGREEN="\033[1;32m"
BYELLOW="\033[1;33m"
BBLUE="\033[1;34m"
BPURPLE="\033[1;35m"
BCYAN="\033[1;36m"
BWHITE="\033[1;37m"

# Prefix format
PREFIX="${BBLUE}[${BCYAN}AWS-KVS${BBLUE}]${RESET}"
INFO="${PREFIX} ${BCYAN}[INFO]${RESET}"
SUCCESS="${PREFIX} ${BGREEN}[SUCCESS]${RESET}"
WARN="${PREFIX} ${BYELLOW}[WARN]${RESET}"
ERROR="${PREFIX} ${BRED}[ERROR]${RESET}"
STEP="${PREFIX} ${BPURPLE}>>>${RESET}"

# Make sure we are in the script directory
cd "$(dirname "$0")"

echo -e "\n${STEP} ${BWHITE}Checking prerequisites (Mac/Linux)${RESET}"
echo -e "${BYELLOW}---------------------------------------------------${RESET}"

if [[ "$OSTYPE" == "darwin"* ]]; then
    if ! command -v brew >/dev/null 2>&1; then
        echo -e "${WARN} ${BYELLOW}Installing Homebrew...${RESET}"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        echo -e "${SUCCESS} ${GREEN}Homebrew is installed.${RESET}"
    fi

    if ! command -v aws >/dev/null 2>&1; then
        echo -e "${WARN} ${BYELLOW}Installing AWS CLI...${RESET}"
        brew install awscli
    else
        echo -e "${SUCCESS} ${GREEN}AWS CLI is installed.${RESET}"
    fi

    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${WARN} ${BYELLOW}Installing Docker...${RESET}"
        brew install --cask docker
        echo -e "${INFO} ${CYAN}Opening Docker. Please finish any setup prompts and allow it to initialize.${RESET}"
        open -a Docker
    else
        echo -e "${SUCCESS} ${GREEN}Docker is installed.${RESET}"
    fi

    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo -e "${WARN} ${BYELLOW}Installing FFmpeg...${RESET}"
        brew install ffmpeg
    else
        echo -e "${SUCCESS} ${GREEN}FFmpeg is installed.${RESET}"
    fi
else
    if ! command -v aws >/dev/null 2>&1; then
        echo -e "${WARN} ${BYELLOW}Installing AWS CLI...${RESET}"
        sudo apt-get update && sudo apt-get install -y awscli
    else
        echo -e "${SUCCESS} ${GREEN}AWS CLI is installed.${RESET}"
    fi
    
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${WARN} ${BYELLOW}Installing Docker...${RESET}"
        sudo apt-get update && sudo apt-get install -y docker.io docker-compose-v2
    else
        echo -e "${SUCCESS} ${GREEN}Docker is installed.${RESET}"
    fi
    
    if ! command -v ffmpeg >/dev/null 2>&1; then
        echo -e "${WARN} ${BYELLOW}Installing FFmpeg...${RESET}"
        sudo apt-get update && sudo apt-get install -y ffmpeg
    else
        echo -e "${SUCCESS} ${GREEN}FFmpeg is installed.${RESET}"
    fi
fi

echo -e "\n${STEP} ${BWHITE}Waiting for Docker to be ready...${RESET}"
echo -e "${BYELLOW}---------------------------------------------------${RESET}"
while ! docker info >/dev/null 2>&1; do
    echo -e "${WARN} ${YELLOW}Wait for docker daemon... (If Docker Desktop is not open, please open it)${RESET}"
    sleep 5
done
echo -e "${SUCCESS} ${GREEN}Docker is ready.${RESET}"

echo -e "\n${STEP} ${BWHITE}AWS Configuration Check${RESET}"
echo -e "${BYELLOW}---------------------------------------------------${RESET}"
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo -e "${WARN} ${YELLOW}AWS CLI is not configured or session expired. Asking for configuration...${RESET}"
    aws configure
else
    echo -e "${SUCCESS} ${GREEN}AWS is configured, moving on...${RESET}"
fi

echo -e "\n${STEP} ${BWHITE}Authenticating Docker to AWS ECR${RESET}"
echo -e "${BYELLOW}---------------------------------------------------${RESET}"
aws ecr get-login-password --region us-west-2 | docker login -u AWS --password-stdin https://546150905175.dkr.ecr.us-west-2.amazonaws.com

echo -e "\n${STEP} ${BWHITE}Determining OS to choose correct AWS KVS image${RESET}"
echo -e "${BYELLOW}---------------------------------------------------${RESET}"
OS_TYPE=$(uname)
if [[ "$OS_TYPE" == *"MINGW"* ]] || [[ "$OS_TYPE" == *"CYGWIN"* ]] || [[ "$OS_TYPE" == *"MSYS"* ]]; then
    export KVS_IMAGE_SUFFIX="windows"
    echo -e "${INFO} ${CYAN}Windows detected via bash. Image suffix: windows${RESET}"
else
    export KVS_IMAGE_SUFFIX="linux"
    echo -e "${INFO} ${CYAN}Mac/Linux detected. Image suffix: linux${RESET}"
fi

echo -e "\n${STEP} ${BWHITE}Cleaning up any old conflicting containers...${RESET}"
echo -e "${BYELLOW}---------------------------------------------------${RESET}"
docker rm -f mediamtx kinesis-producer >/dev/null 2>&1 || true

echo -e "\n${STEP} ${BWHITE}Starting services using Docker Compose${RESET}"
echo -e "${BYELLOW}---------------------------------------------------${RESET}"
docker compose up -d --quiet-pull

echo -e "\n${STEP} ${BWHITE}Services Started! Waiting for mediamtx to warm up...${RESET}"
echo -e "${BYELLOW}---------------------------------------------------${RESET}"
sleep 5

echo -e "\n${STEP} ${BWHITE}Starting Camera Stream...${RESET}"
echo -e "${BYELLOW}---------------------------------------------------${RESET}"
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e "${INFO} ${CYAN}Starting Mac Camera using FFmpeg... (Press Ctrl+C to stop)${RESET}"
    # 0 is usually the built-in FaceTime HD Camera; none ignores audio
    ffmpeg -f avfoundation -framerate 30 -video_size 1280x720 -i "0:none" -c:v libx264 -preset ultrafast -tune zerolatency -b:v 1500k -rtsp_transport tcp -f rtsp rtsp://localhost:8554/mystream || echo -e "${ERROR} ${BRED}Failed to start camera. Make sure terminal has camera permission and correct device ID is used.${RESET}"
else
    echo -e "${INFO} ${CYAN}Starting Linux Camera (v4l2)...${RESET}"
    ffmpeg -f v4l2 -framerate 30 -video_size 1280x720 -i /dev/video0 -c:v libx264 -preset ultrafast -tune zerolatency -b:v 1500k -rtsp_transport tcp -f rtsp rtsp://localhost:8554/mystream || echo -e "${ERROR} ${BRED}Failed to start camera.${RESET}"
fi
