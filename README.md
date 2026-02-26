# 🌟 Amazon Kinesis Video Streams (KVS) RTSP Producer: The Ultimate Guide 🌟

Welcome to the most comprehensive, end-to-end, fully Dockerized solution for bridging local or remote RTSP/RTMP video streams directly to **Amazon Kinesis Video Streams (KVS)**. 

If you are looking to build a scalable, cloud-native video ingestion pipeline, you have found the right repository. This guide covers every single aspect of the project, from the underlying architecture and AWS configuration to advanced GStreamer pipeline tuning and low-latency network optimization.

---

## 📑 Table of Contents

1. [Project Overview & Philosophy](#1-project-overview--philosophy)
2. [Why This Tech Stack?](#2-why-this-tech-stack)
3. [Deep Dive: Architecture & Data Flow](#3-deep-dive-architecture--data-flow)
4. [Comprehensive Prerequisites](#4-comprehensive-prerequisites)
5. [AWS Cloud Configuration Setup](#5-aws-cloud-configuration-setup)
6. [Security & Environment Variables (`.env`)](#6-security--environment-variables-env)
7. [Installation & Deployment](#7-installation--deployment)
8. [Understanding the Components](#8-understanding-the-components)
   - [The Docker Compose Strategy](#the-docker-compose-strategy)
   - [MediaMTX: The Gateway](#mediamtx-the-gateway)
   - [GStreamer Pipeline Mechanics](#gstreamer-pipeline-mechanics)
9. [Ingesting Video into MediaMTX](#9-ingesting-video-into-mediamtx)
   - [Using Physical IP Cameras](#using-physical-ip-cameras)
   - [Simulating with FFmpeg](#simulating-with-ffmpeg)
   - [Broadcasting with OBS Studio](#broadcasting-with-obs-studio)
10. [Verifying Stream in AWS KVS](#10-verifying-stream-in-aws-kvs)
11. [Advanced Configuration & Tuning](#11-advanced-configuration--tuning)
12. [Performance & Latency Optimization](#12-performance--latency-optimization)
13. [Security Best Practices](#13-security-best-practices)
14. [Massive Troubleshooting Guide](#14-massive-troubleshooting-guide)
15. [Operation & Maintenance](#15-operation--maintenance)
16. [Frequently Asked Questions (FAQ)](#16-frequently-asked-questions-faq)
17. [Conclusion & License](#17-conclusion--license)

---

## 1. Project Overview & Philosophy

In modern IoT and computer vision environments, securely reliably moving live video from local sites (factories, homes, retail stores) to the cloud is a critical challenge. Direct streaming to AWS KVS from edge devices often fails due to complex C++ SDK compilation requirements, missing TLS certificates, or varied local network topologies.

**The Solution:**
This project standardizes the ingestion process by creating a locally hosted, Docker-containerized "Bridge".
1. Local cameras send their standard RTSP feeds to a local server (MediaMTX).
2. The custom KVS Producer container picks up that feed, formats it specifically for AWS, and securely pushes it to Kinesis.

This decouples the camera hardware from the cloud complexities, allowing you to use *any* RTSP-capable camera (Hikvision, Dahua, Unifi, generic webcams via OBS) and stream it seamlessly to AWS.

## 2. Why This Tech Stack?

### Amazon Kinesis Video Streams (KVS)
AWS KVS is a fully managed service that securely streams video from connected devices to AWS for analytics, machine learning (Amazon Rekognition), playback, and other processing. It automatically provisions and elastically scales all the infrastructure needed to ingest streaming video data from millions of devices.

### MediaMTX (formerly rtsp-simple-server)
MediaMTX is incredibly lightweight, written in Go, and acts as the perfect local proxy. It translates protocols on the fly (RTSP, RTMP, HLS, WebRTC) without demanding heavy CPU cycles.

### Docker & Docker Compose
By containerizing both the MediaMTX server and the AWS KVS C++ SDK producer, we eliminate the "it works on my machine" problem. The AWS C++ SDK is notoriously difficult to compile manually (requiring specific versions of CMake, GCC, GStreamer, OpenSSL, and cURL). Our `docker-compose.yml` abstracts all of this into a single command.

---

## 3. Deep Dive: Architecture & Data Flow

To master this system, you must understand the exact journey of a single video frame.

```text
[Camera/OBS/FFmpeg] ---> (Protocol: RTSP/RTMP) ---> [Docker Host Network]
                                                            |
                                                            v
[AWS KVS Cloud] <--- (HTTPS / TLS 1.2 Encrypted) <--- [KVS Kinesis Producer (GStreamer)] <--- (Protocol: Internal RTSP) <--- [MediaMTX Container]
    ^                                                                                                                             |
    |                                                                                                                             |
    +--- Validates credentials against AWS IAM <--- [ .env file (Local secrets) ]                                                 |
```

**Step-by-Step Flow:**
1. **Source Generation**: A sensor captures a frame, encodes it to H.264 (AVC).
2. **Local Transport**: The stream is pushed to `rtsp://<local-host-ip>:8554/mystream`.
3. **MediaMTX Ingestion**: The `mediamtx` container receives it. It holds the stream in memory.
4. **GStreamer Pull**: The KVS producer container runs `gst-launch-1.0`. It acts as an RTSP client (`rtspsrc`), pulling from `mediamtx` on the internal Docker network (`rtsp://mediamtx:8554/mystream`).
5. **Payload Processing**: The stream is stripped of its RTSP/RTP transport layer (`rtph264depay`), ensuring we only have raw H.264 `nal` units.
6. **AWS Plugin Integration**: The custom AWS `kvssink` plugin takes the H.264 stream. It buffers it locally.
7. **Cloud Transmission**: Using the `.env` credentials, it connects to AWS, acquires an endpoint, and streams MKV fragments (managed automatically by the SDK) over port 443 (HTTPS) to the `CAM` stream in your AWS account.

---

## 4. Comprehensive Prerequisites

You cannot proceed without ensuring your host and cloud environments are perfectly prepared.

### 4.1 Host System Requirements
- **Operating System**: Linux (Ubuntu 20.04/22.04, Debian, Amazon Linux 2), macOS (Intel or Apple Silicon), or Windows 10/11 (with WSL2 enabled).
- **RAM**: Minimum 2GB (4GB recommended for caching).
- **CPU**: Minimal usage unless transcoding is introduced. The current passthrough pipeline uses negligible CPU.
- **Network**: A stable outbound internet connection capable of sustaining the upload bitrate of your camera (e.g., a 1080p stream typically requires 2-4 Mbps of continuous upload speed).

### 4.2 Software Dependencies
- **Docker Engine**: Version 20.10.0 or higher.
  - *Verify*: `docker --version`
- **Docker Compose**: V2 recommended (`docker compose`), but V1 (`docker-compose`) is supported.
  - *Verify*: `docker-compose --version`
- **Git**: For cloning the repository.
  - *Verify*: `git --version`

### 4.3 AWS Requirements
- Complete administrative access to an AWS account (or an IAM user with sufficient privileges to create other IAM users and generic policies).

---

## 5. AWS Cloud Configuration Setup

Before touching the code, we must construct the cloud infrastructure and security parameters.

### Step 5.1: Create the IAM User
AWS KVS requires programmatic credentials. We do not use root AWS accounts for this.
1. Log in to the AWS IAM Console (Identity and Access Management).
2. Navigate to **Users** -> **Add users**.
3. User name: `KVS-Producer-Edge-Device`.
4. Select **Access key - Programmatic access** (or generate an Access Key in the Security credentials tab later).
5. Click **Next: Permissions**.

### Step 5.2: Attach Permissions
You should apply the principle of least privilege. Do **not** use `AdministratorAccess`.
1. Select **Attach existing policies directly**.
2. Search for the managed policy: `AmazonKinesisVideoStreamsFullAccess`.
   - *Alternative (Strict Security)*: Create a custom JSON policy:
     ```json
     {
         "Version": "2012-10-17",
         "Statement": [
             {
                 "Effect": "Allow",
                 "Action": [
                     "kinesisvideo:PutMedia",
                     "kinesisvideo:DescribeStream",
                     "kinesisvideo:GetDataEndpoint",
                     "kinesisvideo:CreateStream",
                     "kinesisvideo:TagStream"
                 ],
                 "Resource": "arn:aws:kinesisvideo:us-east-1:YOUR_ACCOUNT_ID:stream/CAM/*"
             }
         ]
     }
     ```
3. Proceed and create the user.

### Step 5.3: Save Credentials
Upon creation, AWS provides:
- **Access key ID** (starts with `AKIA...`)
- **Secret access key** (A long string of random characters)
Keep this screen open or download the CSV. You will need these for the `.env` file.

---

## 6. Security & Environment Variables (`.env`)

**WARNING: NEVER COMMIT SECRETS TO GIT.**
The system relies on a `.env` file to inject sensitive AWS credentials into the Docker containers at runtime. This repository includes a `.gitignore` that prevents `.env` from being tracked.

Create a file named precisely `.env` in the root folder of this project:

```ini
# ==============================================================================
# 🔐 AWS KVS AUTHENTICATION BINDINGS 🔐
# ==============================================================================

# 1. AWS Access Key ID
# The public identifier for your IAM User. Usually 20 characters long.
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE

# 2. AWS Secret Access Key
# The private key for your IAM User. Usually 40 characters long.
# Do not use quotation marks around this value unless it contains weird characters.
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY

# 3. AWS Region
# The specific Amazon data center where your stream will reside.
# KVS pricing varies slightly by region. Choose the one closest to your edge device.
# Common regions: us-east-1 (N. Virginia), us-west-2 (Oregon), eu-west-1 (Ireland).
AWS_REGION=us-east-1

# Optional override (used in docker-compose.yml for dynamic tags)
# KVS_IMAGE_SUFFIX=linux
```

*Troubleshooting the `.env` file:* Ensure there are absolutely no trailing spaces at the ends of the lines. A trailing space on the secret key will result in an "Invalid Signature" error from AWS.

---

## 7. Installation & Deployment

With AWS prepared and your `.env` configured, you are ready to launch the infrastructure.

### 7.1 Clone the Repository
Open your terminal or command prompt:
```bash
git clone https://github.com/your-username/kinesis-video-producer.git
cd kinesis-video-producer
```

### 7.2 Bootstrapping the Services
You have multiple ways to initialize the stack depending on your OS.

**Method A: Native Docker Compose (Universal)**
```bash
# Pull the latest images and start containers in the background (-d)
docker-compose up -d

# Verify they are running:
docker-compose ps
```

**Method B: Linux / macOS Shell Script**
We have provided a convenient `start.sh` wrapper.
```bash
# Make the script executable
chmod +x start.sh
# Run the deployment
./start.sh
```

**Method C: Windows Batch Script**
If you are running Docker Desktop on Windows:
Double-click `start.bat` or run it from the Command Prompt.

### 7.3 Verifying Logs
Immediately after triggering the deployment, you must check the logs to ensure the AWS SDK is initializing and MediaMTX is bound to the ports.
```bash
docker-compose logs -f
```
Expected output:
- `mediamtx`: "listener opened on :8554 (rtsp)"
- `kinesis-producer`: "Setting pipeline to PAUSED... Pipeline is PREROLLING..."

---

## 8. Understanding the Components

Let's dissect exactly what runs on your machine.

### The Docker Compose Strategy
The `docker-compose.yml` file is the orchestrator.
- **Networks**: Both containers share a default custom bridge network. This allows `kinesis-producer` to communicate with `mediamtx` simply by using its hostname (`rtsp://mediamtx:...`), entirely bypassing the host's networking stack for internal communication.
- **Restart Policies**: Both use `restart: always`. If the machine reboots, or if the GStreamer pipeline crashes due to a bad frame, Docker will automatically resurrect the containers.

### MediaMTX: The Gateway
Defined in `mediamtx.yml` (mapped as a volume) and exposed on standard ports:
- `8554`: TCP/UDP for RTSP traffic.
- `8000/8001`: UDP ports for RTP/RTCP data.
MediaMTX is completely passive. It waits for publishers to push video to a path, and then allows readers (like our AWS producer) to pull from that path. We use the path `mystream`.

### GStreamer Pipeline Mechanics
The core of this project is a single line of code executed in the `kinesis-producer` container:
```bash
gst-launch-1.0 -v rtspsrc location="rtsp://mediamtx:8554/mystream" short-header=TRUE latency=100 ! rtph264depay ! h264parse ! video/x-h264,stream-format=avc,alignment=au ! kvssink stream-name="CAM" storage-size=512 access-key="${AWS_ACCESS_KEY_ID}" secret-key="${AWS_SECRET_ACCESS_KEY}" aws-region="${AWS_REGION}"
```
Let's break down this complex pipeline:
- `gst-launch-1.0`: The command-line tool to quickly build GStreamer graphs.
- `-v`: Verbose output (crucial for debugging state changes).
- `rtspsrc location=...`: The source element. It acts as an RTSP client pulling from MediaMTX.
- `latency=100`: Reduces the jitter buffer to 100ms. If you have packet loss over Wi-Fi, increase this to 500 or 1000.
- `!`: The pipe symbol connecting elements.
- `rtph264depay`: As RTSP transports video via RTP packets, this strips the RTP headers to extract the raw H.264 data.
- `h264parse`: Parses the raw stream, extracting Sequence Parameter Sets (SPS) and Picture Parameter Sets (PPS), ensuring the frame boundaries are correct.
- `video/x-h264,stream-format=avc,alignment=au`: A "caps filter" forcing the stream into Access Units (AU) formatted as AVC. AWS KVS `kvssink` strictly demands this exact format.
- `kvssink`: The proprietary element compiled by AWS. It creates the Fragmented MP4 (MKV) wrapper, handles TLS connections, authenticates via IAM, and streams to the cloud.
- `storage-size=512`: Allocates 512 Megabytes of internal RAM buffer. If your internet disconnects temporarily, `kvssink` will store frames in RAM and batch upload them when the connection is restored!

---

## 9. Ingesting Video into MediaMTX

Your KVS pipeline is now waiting. It will sit at a "prerolling" stage until it actually receives video frames. You must push a stream to `rtsp://<docker-host-ip>:8554/mystream`.

### Using Physical IP Cameras (Hikvision, Dahua, Axis)
Physical cameras act as RTSP servers. Since MediaMTX is also an RTSP server, you cannot point a camera directly at MediaMTX without an active puller. 
To proxy a physical camera, you would modify the `.env` or Docker command to skip MediaMTX entirely and point GStreamer directly at the camera:
*Example modification in `docker-compose.yml`:*
```yaml
command: >
  gst-launch-1.0 -v rtspsrc location="rtsp://admin:password123@192.168.1.108:554/cam/realmonitor?channel=1&subtype=0" ...
```

### Simulating with FFmpeg (The easiest testing method)
If you just want to test if AWS works, use a local `.mp4` file and loop it infinitely using FFmpeg.
Install FFmpeg on your local machine and run:
```bash
ffmpeg -re -stream_loop -1 -i test_vid.mp4 -c:v copy -f rtsp rtsp://127.0.0.1:8554/mystream
```
- `-re`: Reads the file at native frame rates (real-time).
- `-c:v copy`: Does not transcode; copies the H.264 blocks directly. (Your test video MUST be H.264!).

### Broadcasting with OBS Studio
OBS is fantastic for mixing webcams, screens, and audio.
1. Download [OBS Studio](https://obsproject.com/).
2. Click **Settings** -> **Stream**.
3. Service: `Custom...`
4. Server: `rtsp://127.0.0.1:8554/`
5. Stream Key: `mystream`
6. Click **Settings** -> **Output** -> Advanced Mode.
7. Encoder: MUST BE `x264`, `QuickSync H.264`, `NVENC H.264`, or `Apple VT H264`. KVS does not support AV1 or VP9 directly through this generic pipeline.
8. Uncheck "Use custom buffer size". Set Bitrate to `2000 Kbps`.
9. Click **Start Streaming**.
Within 3 seconds, you will see KVS Producer logs light up "Pipeline is PLAYING".

---

## 10. Verifying Stream in AWS KVS

Data is being pushed to the cloud. Let's watch it.
1. Open your web browser and navigate to the [AWS Console](https://console.aws.amazon.com).
2. Ensure you are in the exact region specified in your `.env` (e.g., `us-east-1` N. Virginia is top right).
3. Search for **Kinesis Video Streams**.
4. In the left menu, click **Video streams**.
5. You will see a stream named **`CAM`**. 
   *(Note: The `kvssink` plugin automatically creates the stream in AWS if it does not exist, assuming your IAM user has the `kinesisvideo:CreateStream` permission).*
6. Click the stream name.
7. Expand the **Media playback** interface.
8. Hit play. You should now see your live feed, usually with a glass-to-glass latency of 3 to 8 seconds, depending on HLS player buffering.

---

## 11. Advanced Configuration & Tuning

The true power of this stack is its flexibility.

### 11.1 Renaming the AWS Stream
If you have 5 different edge devices, they cannot all push to a stream named `CAM`.
To modify this, edit your `docker-compose.yml`:
Look for `stream-name="CAM"` and change it to `stream-name="Warehouse-Cam-01"`. Apply changes by running `docker-compose up -d --force-recreate`.

### 11.2 Adding Audio Injection
AWS KVS supports AAC audio multiplexed with H.264. This requires a significantly heavier GStreamer pipeline.
*Conceptual audio+video pipeline:*
```bash
gst-launch-1.0 -v \
  kvssink name=sink stream-name="CAM" access-key="${AWS_ACCESS_KEY_ID}" secret-key="${AWS_SECRET_ACCESS_KEY}" aws-region="${AWS_REGION}" \
  rtspsrc location="rtsp://mediamtx:8554/mystream" name=src \
  src. ! rtph264depay ! h264parse ! video/x-h264,stream-format=avc,alignment=au ! sink.video \
  src. ! rtpmp4gdepay ! aacparse ! sink.audio
```
*(Note: Implementing audio requires extensive knowledge of your specific camera's RTSP audio tracks).*

### 11.3 Changing Time-To-Live (Data Retention)
By default, auto-created KVS streams might have a default retention of 2 hours or 0 hours. You can adjust this via AWS Console -> Stream -> Edit Data Retention. If it is 0 hours, the stream only supports WebRTC/Live, and normal HLS playback via console might behave eratically. Set it to 24 hours for testing.

---

## 12. Performance & Latency Optimization

Video streaming is sensitive to network interruptions.

### 12.1 The `storage-size` parameter
In `docker-compose.yml`: `storage-size=512`.
This allocates memory inside the KVS SDK. If your upload bandwidth drops, the SDK buffers video in RAM. 512MB can hold several minutes of 1080p video. If deploying to a Raspberry Pi with 1GB RAM, lower this to `storage-size=128`.

### 12.2 Dropping frames on slow connections
If your edge router internet limits are 1Mbps, but the camera is sending 4Mbps, the RAM buffer will fill up. Eventually, KVS will throw a fatal error.
You must lower the bitrate on the source (the physical IP camera's web interface) to match your physical ISP upload capabilities.

### 12.3 Time Synchronization (CRITICAL)
AWS enforces stringent cryptographic signing. If the clock on the machine running Docker drifts by more than 5 minutes from actual NTP time, AWS will reject the API calls with a `SignatureDoesNotMatch` or `InvalidToken` error. Make sure your local machine uses `ntpd` or systemd-timesyncd to maintain accurate clocks.

---

## 13. Security Best Practices

To move this project from experimental to production:

1. **Restrict IAM Policies**: Never use `AmazonKinesisVideoStreamsFullAccess` in production. Bind the IAM policy's `Resource` block to the exact ARN of the specific stream.
2. **Docker User Mapping**: Avoid running `gst-launch` as root. (Advanced: rebuild the image with a dedicated user).
3. **Firewalling MediaMTX**: Do not open port `8554` to the public internet on your router. MediaMTX currently has no username/password configured in this barebones setup. Local subnet traffic only.
4. **.env Encryption**: In Enterprise setups, replace the `.env` file injection with AWS Secrets Manager or HashiCorp Vault.

---

## 14. Massive Troubleshooting Guide

Encountered an error? Don't panic. Here are the 15 most common issues and exactly how to fix them.

### Error 1: `Unauthorized` / `Invalid Signature` in Docker logs
**Symptoms**: `kvssink` fails immediately upon connecting to AWS.
**Cause**: 
1. The `.env` variables are incorrect, or missing.
2. The IAM user lacks permissions.
3. System clock drift.
**Fix**: Double check `.env`. Ensure your terminal in VSCode didn't accidentally add a trailing space. Ensure your OS time is synced. Run `docker-compose config` to see if `.env` is loading properly.

### Error 2: `no element "kvssink"`
**Symptoms**: The container immediately crashes with a GStreamer syntax error.
**Cause**: The custom AWS plugin was not loaded by GStreamer.
**Fix**: You might be using a generic Alpine/Ubuntu image instead of the mandated AWS SDK image. Ensure `image: 546150905175.dkr.ecr...` is precisely set in your compose file.

### Error 3: KVS Console plays video, but it goes gray/green, or freezes.
**Symptoms**: Playback is corrupted.
**Cause**: Missing I-Frames (Keyframes). AWS needs a full frame (I-Frame) to start playback. If your camera only sends an I-Frame every 10 seconds, AWS has to wait 10 seconds to render the stream.
**Fix**: Log into your physical IP Camera's interface. Find "Video Settings". Set "Keyframe Interval" or "I-Frame Interval" to match your Framerate (e.g., if recording at 30fps, set I-Frame interval to 30. This forces 1 I-Frame per second).

### Error 4: Pipeline remains in `PREROLLING` forever.
**Symptoms**: `kinesis-producer` logs say "Setting pipeline to PAUSED... Pipeline is PREROLLING..." and never says "PLAYING".
**Cause**: The `kvssink` element is waiting for video data, but MediaMTX isn't receiving any stream, or is receiving a non-H264 stream.
**Fix**: Ensure your FFmpeg/OBS/Camera is actively pushing to the `rtsp://<ip>:8554/mystream` path with an H.264 codec.

### Error 5: MediaMTX "bind: address already in use"
**Symptoms**: MediaMTX container keeps restarting.
**Cause**: You already have another program (like another MediaMTX, VLC Server, or a local IP device) utilizing network port `8554` or `8000`.
**Fix**: Edit `docker-compose.yml` and change the mapping to `- "18554:8554"`.

### Error 6: High Latency (15+ seconds)
**Cause**: HTTP Live Streaming (HLS) in the AWS Console buffers segments before playing. 
**Fix**: This is architectural. For ultra-low sub-second latency, you cannot use the KVS HLS dashboard. You must implement Amazon KVS WebRTC (a separate protocol entirely from standard KVS streaming).

### Error 7: Fragment duration exceeds limits
**Symptoms**: KVS SDK drops fragments indicating they are too large or too long.
**Fix**: Again, adjust your camera's I-Frame interval. KVS fragments chunks based on I-Frames.

### Error 8: Out of Memory (OOM Killer) in Linux
**Symptoms**: Container randomly dies with Exit Code 137.
**Fix**: `kvssink` used up the 512MB RAM buffer due to terrible network. Either fix the network upload speeds or increase system swap space.

### Error 9: Hostname `mediamtx` not resolved.
**Symptoms**: `rtspsrc` fails because it can't find `rtsp://mediamtx`.
**Fix**: Ensure both containers are in the exact same `docker-compose.yml` file under the same `services` block so Docker's internal DNS daemon maps it automatically.

### Error 10: "Can't link rtspsrc to rtph264depay"
**Cause**: The RTSP source is providing H.265 (HEVC), not H.264.
**Fix**: Go into your camera settings and explicitly downgrade the Video Compression standard from H.265 to H.264. 

---

## 15. Operation & Maintenance

### Daily Operations
- Monitor your AWS Billing dashboard. KVS charges a few cents per gigabyte ingested, plus fragment retrieval fees. High-bitrate 24/7 streams add up.
- Use Docker log rotation if you plan to keep this running permanently to avoid filling your server's disk space:
  *Example (Docker config):*
  ```yaml
  logging:
    driver: "json-file"
    options:
      max-size: "10m"
      max-file: "3"
  ```

### Re-Deployment
If you update `.env` or `docker-compose.yml`:
```bash
docker-compose down
docker-compose pull
docker-compose up -d
```

---

## 16. Frequently Asked Questions (FAQ)

**Q: Can this run on a Raspberry Pi?**
A: Yes, assuming you use an ARM64 compiled `kinesis-video-producer-sdk` image. However, the exact AWS ECR base image defined might be AMD64 specific depending on the AWS region's registry. If so, you will need to compile the AWS KVS C++ SDK yourself from source on the Pi.

**Q: Does it support RTSP with usernames and passwords?**
A: Yes, if your IP camera requires auth, use `rtsp://user:pass@192.168.0.x:554/stream` in the GStreamer pipeline string.

**Q: Can I stream multiple cameras simultaneously?**
A: You can, but you need to duplicate the producer service in `docker-compose.yml`:
```yaml
  kinesis-producer-cam1:
    command: gst-launch-1.0 ... rtsp://.../mystream1 ... kvssink stream-name="CAM1" ...
  kinesis-producer-cam2:
    command: gst-launch-1.0 ... rtsp://.../mystream2 ... kvssink stream-name="CAM2" ...
```

**Q: What happens if AWS goes down?**
A: The SDK writes internally to the `storage-size` buffer. If the buffer is exhausted before AWS recovers, frames are permanently dropped. Your local MediaMTX will continue operating locally without issues.

---

## 17. Conclusion & License

By following this extensive guide, you have successfully bridged the gap between legacy local hardware and massive highly-available cloud infrastructure. You now possess a production-ready edge pipeline.

**License**: MIT License. You are free to modify, distribute, and integrate this locally and commercially.

*Documentation version: 2.5.*
*Last updated for KVS SDK v3.x / MediaMTX v1.x.*

---
*End of Document*
