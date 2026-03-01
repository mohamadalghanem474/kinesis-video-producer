# AWS Kinesis Video Producer

Stream your camera to **Amazon Kinesis Video Streams** using two separate containers:

| Container          | AWS Service                                   | Latency    | Description                              |
| ------------------ | --------------------------------------------- | ---------- | ---------------------------------------- |
| `kinesis-producer` | **Video Streams** (`CAM`)                     | ~5 seconds | Records video for HLS playback & storage |
| `kvs-webrtc`       | **Signaling Channels** (`CAM-WEBRTC-CHANNEL`) | < 1 second | Real-time WebRTC viewer                  |

## Architecture

```
📷 Camera (FFmpeg → RTSP)
        │
        ▼
┌──────────────────────────────┐
│       mediamtx (RTSP Server) │
│       Port 8554              │
└──────┬───────────────┬───────┘
       │               │
       ▼               ▼
┌──────────────┐ ┌─────────────────┐
│ kinesis-     │ │ kvs-webrtc      │
│ producer     │ │                 │
│              │ │ Signaling       │
│ Video Stream │ │ Channel         │
│ "CAM"        │ │ "CAM-WEBRTC-    │
│ (~5s delay)  │ │  CHANNEL"       │
│              │ │ (<1s delay)     │
└──────────────┘ └─────────────────┘
```

---

## Prerequisites

### Mac

```bash
# Install Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required tools
brew install awscli ffmpeg
brew install --cask docker
```

### Windows

```powershell
# Install using winget
winget install -e --id Amazon.AWSCLI
winget install -e --id Docker.DockerDesktop
winget install -e --id Gyan.FFmpeg
```

> **Important**: After installing, restart your terminal so the commands are available.

---

## Step 1: Configure AWS

```bash
aws configure
```

Enter your:
- **AWS Access Key ID**
- **AWS Secret Access Key**
- **Default region** (e.g. `us-east-1`)

---

## Step 2: Create `.env` File

Copy the example and fill in your credentials:

```bash
cp .example.env .env
```

Edit `.env`:
```
AWS_ACCESS_KEY_ID=YOUR_ACCESS_KEY
AWS_SECRET_ACCESS_KEY=YOUR_SECRET_KEY
AWS_REGION=us-east-1
```

---

## Step 3: Authenticate Docker to AWS ECR

```bash
aws ecr get-login-password --region us-west-2 | docker login -u AWS --password-stdin https://546150905175.dkr.ecr.us-west-2.amazonaws.com
```

---

## Step 4: Start Docker

Make sure **Docker Desktop** is running before proceeding.

- **Mac**: Open Docker from Applications
- **Windows**: Open Docker Desktop from Start Menu

Verify Docker is ready:
```bash
docker info
```

---

## Step 5: Start the Containers

```bash
docker compose up -d
```

> **Note**: The first run will build the `kvs-webrtc` image from source (~30 minutes). Subsequent runs use cached image and start instantly.

Check status:
```bash
docker ps
```

You should see 3 running containers: `mediamtx`, `kinesis-producer`, `kvs-webrtc`.

---

## Step 6: Start Camera Stream

Open a **new terminal** and run:

### Mac
```bash
ffmpeg -f avfoundation -framerate 30 -video_size 1280x720 -i "0:none" \
  -c:v libx264 -preset ultrafast -tune zerolatency -b:v 1500k \
  -rtsp_transport tcp -f rtsp rtsp://localhost:8554/mystream
```

> If the camera doesn't work, find your device ID:
> ```bash
> ffmpeg -f avfoundation -list_devices true -i ""
> ```
> Replace `"0:none"` with your camera index.

### Windows
```powershell
ffmpeg -f dshow -i video="Integrated Camera" -c:v libx264 -preset ultrafast -tune zerolatency -b:v 1500k -rtsp_transport tcp -f rtsp rtsp://localhost:8554/mystream
```

> If the camera doesn't work, find your device name:
> ```powershell
> ffmpeg -list_devices true -f dshow -i dummy
> ```
> Replace `"Integrated Camera"` with your camera name.

---

## Viewing the Stream

### Video Streams (HLS — ~5s delay)
1. Go to [AWS KVS Console](https://console.aws.amazon.com/kinesisvideo/home)
2. Select **Video streams** → `CAM`
3. Click **Media playback**

### Signaling Channels (WebRTC — <1s delay)
1. Go to [AWS KVS Console](https://console.aws.amazon.com/kinesisvideo/home)
2. Select **Signaling channels** → `CAM-WEBRTC-CHANNEL`
3. Click **Media playback**

---

## Useful Commands

```bash
# Start all containers
docker compose up -d

# Stop all containers
docker compose down

# View logs
docker logs kinesis-producer --tail 20
docker logs kvs-webrtc --tail 20
docker logs mediamtx --tail 20

# Restart a specific container
docker compose restart kvs-webrtc

# Rebuild WebRTC image (only needed if docker-compose.yml changes)
docker compose build kvs-webrtc

# Clean up everything
docker compose down --rmi all --volumes
```

---

## Files

| File                 | Purpose                                      |
| -------------------- | -------------------------------------------- |
| `docker-compose.yml` | All containers + inline WebRTC Dockerfile    |
| `.env`               | AWS credentials (create from `.example.env`) |
| `.example.env`       | Template for `.env` file                     |

---

## Troubleshooting

| Problem                             | Solution                                                       |
| ----------------------------------- | -------------------------------------------------------------- |
| `env file .env not found`           | Run `cp .example.env .env` and fill in credentials             |
| `Docker daemon is not running`      | Open Docker Desktop and wait for it to initialize              |
| Camera not detected                 | Check device ID/name (see Step 6)                              |
| `kinesis-producer` keeps restarting | Make sure camera is streaming first (Step 6)                   |
| `kvs-webrtc` no output in logs      | Normal — it runs silently, waiting for WebRTC viewers          |
| Platform warning (amd64/arm64)      | Normal on Mac M1/M2/M3 — `kinesis-producer` runs via emulation |
