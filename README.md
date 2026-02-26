# Amazon Kinesis Video Streams (KVS) RTSP Producer

A robust, fully Dockerized solution designed to bridge local or remote RTSP/RTMP video streams directly to **Amazon Kinesis Video Streams (KVS)**. 

This project orchestrates two main components using Docker Compose:
1. **MediaMTX**: A highly efficient, zero-dependency RTSP/RTMP/LL-HLS media server. It acts as the local hub to receive video streams from your cameras, OBS, or broadcasting software.
2. **AWS KVS Producer (GStreamer)**: A custom-built pipeline leveraging `gst-launch-1.0` inside an AWS-provided SDK container. It consumes the local stream from MediaMTX, processes the H.264 video, and securely transmits it to AWS KVS in real-time.

---

## 🏗️ Architecture & Data Flow

Understanding the flow of video data is crucial for troubleshooting and scaling:

1. **Video Source**: Your IP Camera, OBS Studio, or FFmpeg sends a video feed (RTSP or RTMP) to the local server.
2. **MediaMTX Server (`mediamtx` container)**: Receives the video feed on port `8554` (for RTSP) and exposes an internal stream named `mystream`.
3. **KVS Producer (`kinesis-producer` container)**: 
   - Wait for MediaMTX to start.
   - Connects to `rtsp://mediamtx:8554/mystream`.
   - Uses the GStreamer pipeline to depayload (`rtph264depay`) and parse (`h264parse`) the video.
   - Pushes the raw AVC H.264 packets to the AWS KVS `kvssink` plugin.
4. **AWS Cloud**: The video is stored and playable on the Amazon Kinesis Video Streams console under the stream name **`CAM`**.

---

## 📋 Recommended Prerequisites

Before deploying this stack, ensure your environment meets the following requirements:

- **Docker Component**: 
  - [Docker Engine](https://docs.docker.com/get-docker/) installed.
  - [Docker Compose](https://docs.docker.com/compose/install/) installed (usually bundled with Docker Desktop).
- **AWS Account**:
  - An active AWS Account.
  - An IAM User with programmatic access (Access Key & Secret Key).
  - The IAM User must have permissions attached (either `AmazonKinesisVideoStreamsFullAccess` or a custom policy allowing `kinesisvideo:PutMedia`, `kinesisvideo:GetDataEndpoint`, `kinesisvideo:DescribeStream`).
- **Video Format**: The incoming stream **must** be `H.264` encoded format, as AWS KVS strictly requires H.264 or H.265. This pipeline is hardcoded for `video/x-h264`.

---

## ⚙️ Detailed Installation & Setup

### 1. Clone the repository

Begin by cloning the source code to your local machine or server.

```bash
git clone <your-repository-url>
cd kinesis-video-producer
```

### 2. Configure Environment Variables (`.env`)

The system relies entirely on environment variables to authenticate with AWS securely. We use a `.env` file instead of hardcoding credentials in the `docker-compose.yml` file to protect your security keys.

**Create a new file named `.env` in the root of your project directory.**

Paste the following structure into the file and replace the placeholder values with your actual AWS IAM credentials:

```ini
# --- AWS KVS Authentication Credentials ---
# The Identity ID of your IAM User
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE

# The Secret Key associated with the Identity (Do not share this!)
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

# The AWS Region where your Kinesis Stream ("CAM") will be hosted
AWS_REGION=us-east-1
```

> **🛡️ Security Note / `.gitignore`**: 
> This project has a `.gitignore` file that automatically ignores `.env`. This ensures your highly sensitive AWS keys are never accidentally uploaded or committed to GitHub/GitLab. **Never modify `.gitignore` to track your `.env` file.**

### 3. Start the Docker Services

You can start the environment using the provided helper scripts or standard Docker commands.

**Option A: Using the Startup Scripts (Recommended)**
If you are on Linux or macOS, simply run:
```bash
./start.sh
```
If you are on Windows, double-click or execute:
```cmd
start.bat
```

**Option B: Using Docker Compose Manually**
To run the containers in the background (detached mode):
```bash
docker-compose up -d
```

To view the live logs to ensure both the media server and KVS producer started correctly:
```bash
docker-compose logs -f
```

---

## 🎥 How to Send Video to the Server

Once the containers are running, `mediamtx` is waiting for a video feed on `rtsp://127.0.0.1:8554/mystream`. 

If you don't have an IP camera, you can simulate a stream using FFmpeg or OBS Studio:

### Using FFmpeg (Streaming a local video file)
Open a new terminal and run:
```bash
ffmpeg -re -stream_loop -1 -i sample_video.mp4 -c:v copy -f rtsp rtsp://127.0.0.1:8554/mystream
```

### Using OBS Studio
1. Open OBS Studio and go to **Settings > Stream**.
2. Set **Service** to `Custom...`.
3. Set **Server** to `rtsp://127.0.0.1:8554/`.
4. Set **Stream Key** to `mystream`.
5. Go to **Settings > Output**, and ensure your Video Encoder is set to **x264** or **Hardware (NVENC, Apple VT)**.
6. Click **Start Streaming**.

Within a few seconds, the KVS Producer container will grab this video and upload it to AWS.

---

## ✅ Verifying it works on AWS

1. Log in to the [AWS Management Console](https://aws.amazon.com/console/).
2. Navigate to **Kinesis Video Streams**.
3. Under **Video streams**, you should see a newly created stream named **`CAM`** (or whichever name is set in the `docker-compose.yml`).
4. Click on **`CAM`** and expand the **Media playback** section. 
5. You should see your live video feed playing directly from the cloud!

---

## 🛠 Advanced Troubleshooting & FAQs

**1. I don't see the Video in AWS (No Data retention):**
Ensure that your stream in AWS KVS has data retention enabled. If data retention is set to 0, you might not be able to play back the stream cleanly in the AWS console.

**2. GStreamer error: `no element "kvssink"`:**
This means the image used for `kinesis-producer` did not properly compile the AWS KVS plugin. Ensure you are pulling the correct ECR image specified in the `docker-compose.yml` and that your Docker architecture (ARM64 vs AMD64/x86) is supported.

**3. GStreamer error: `Unauthorized` or `Invalid Signature`:**
This is an authenticaton failure. 
- Double-check your `.env` file. Ensure there are no spaces at the end of the lines.
- Verify your IAM user has `AmazonKinesisVideoStreamsFullAccess`.
- Make sure the `AWS_REGION` matches where you are checking in the AWS Console.

**4. The video is stuttering or lagging heavily:**
Your upload bandwidth might be saturated. Lower the bitrate of the camera or OBS stream. KVS streaming requires a stable, high-upload-speed internet connection.

## 🛑 Stopping & Cleaning Up

To safely stop both containers without losing configuration:
```bash
docker-compose down
```

To entirely wipe the containers and configurations:
```bash
docker-compose down -v --rmi all
```
