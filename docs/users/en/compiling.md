---
title: Compile
type: docs
description: 
author: HUATUO Team
date: 2026-01-11
weight: 3
---

### 1. Build with the Official Image

To isolate the developer’s local environment and simplify the build process, we provide a containerized build method. You can directly use `docker build` to produce an image containing the core collector **huatuo-bamai**, BPF objects, tools, and more. Run the following in the project root directory:

```bash
docker build --target run --network host -t huatuo/huatuo-bamai:latest -f ./Dockerfile .
```

### 2. Build a Custom Image

#### 2.1 Build the Dev Image

```bash
docker build --target devel --network host -t huatuo/huatuo-bamai-dev:latest -f ./Dockerfile .
```

#### 2.2 Run the Dev Container

```bash
docker run -it --privileged --cgroupns=host --network=host \
  -v /path/to/huatuo:/go/huatuo-bamai \
  -w /go/huatuo-bamai \
  huatuo/huatuo-bamai-dev:latest sh
```

#### 2.3 Compile Inside the Container

Run:

```bash
make
```

Once the build completes, all artifacts are generated under `./_output`.

### 3. Build on a Physical Machine or VM

The collector depends on the following tools. Install them based on your local environment:

- make
- git
- clang15
- libbpf
- bpftool
- curl

> Due to significant differences across local environments, build issues may occur.  
> To avoid environment inconsistencies and simplify troubleshooting, we strongly recommend using the **Docker build approach** whenever possible.
