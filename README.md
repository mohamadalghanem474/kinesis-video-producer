# Amazon Kinesis Video Streams (KVS) RTSP Producer

A complete Docker-based solution for producing and streaming RTSP video feeds into Amazon Kinesis Video Streams (KVS). This project uses `mediamtx` as a lightweight RTSP/RTMP server and a custom Dockerized `gst-launch-1.0` pipeline to push streams directly to AWS KVS.

## 🚀 Features

- **MediaMTX**: Ultra-fast media server that can receive your cameras' RTSP/RTMP streams.
- **AWS KVS Integration**: Fully configured Docker container to securely transfer live RTSP streams to Amazon Kinesis Video Streams.
- **Docker Compose**: Single-command deployment and orchestration.
- **Environment Variables**: Secure credential management via `.env` file.

## 📋 Prerequisites

Before you begin, ensure you have the following installed:
- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)
- An active AWS Account with permissions to write to Kinesis Video Streams

---

## ⚙️ Installation & Setup

### 1. Clone the repository

```bash
git clone <your-repository-url>
cd kinesis-video-producer
```

### 2. Configure Environment Variables (`.env`)

The system requires your AWS credentials and region to authenticate and send video streams to KVS. 

Create a `.env` file in the root directory (or use the provided template if available). Copy the contents below and replace them with your actual AWS credentials:

```bash
# .env file
AWS_ACCESS_KEY_ID=your_aws_access_key
AWS_SECRET_ACCESS_KEY=your_aws_secret_key
AWS_REGION=us-east-1
```
> **⚠️ Important:** Never commit your true `.env` file to version control. The repository is already configured to ignore `.env` files via `.gitignore`.

### 3. Start the Services

Once your `.env` file is ready, you can build and start the application in attached mode to verify logs, or detached mode for background running.

**Using Shell Script (Mac/Linux):**
```bash
./start.sh
```

**Using Batch Script (Windows):**
```cmd
start.bat
```

**Using Docker Compose directly:**
```bash
# Run in detached (background) mode
docker-compose up -d

# Check live logs
docker-compose logs -f
```

---

## 📡 Architecture Workflow

1. A device or software streams video into the `mediamtx` server on `rtsp://<server-ip>:8554/mystream`.
2. The `kinesis-producer` service constantly pulls the `mystream` feed from `mediamtx`.
3. It packages the video (decodes and parses H264) using GStreamer.
4. Using the credentials loaded from `.env`, it pushes the video safely to Kinesis Video Streams under the channel/stream name `CAM`.

## 🛑 Stopping the Services

To completely stop and spin down the containers:
```bash
docker-compose down
```

## 🛠 Troubleshooting

- **No video in KVS Console**: Ensure your IAM User has the `AmazonKinesisVideoStreamsFullAccess` policy or specific permissions to Write/Put media to KVS.
- **Unable to map ports**: Check if another instance of a media server or `mediamtx` is running on ports `8554`, `8000`, or `8001`.
- **Bad Credentials**: Verify your `.env` file matches the expected spelling (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`) without leading/trailing spaces.
