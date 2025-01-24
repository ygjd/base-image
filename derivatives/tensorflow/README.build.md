# Building

Note: Currently this image is suitable only for CUDA on linux/amd64

This Dockerfile relies on the structure provided by [Vast.Ai Base images](https://github.com/vast-ai/base-image).

See the example below for building instructions.

```bash
docker buildx build \
    --platform linux/amd64 \
    --build-arg VAST_BASE=vastai/base-image:cuda-12.4.1-cudnn-devel-ubuntu22.04 \
    --build-arg TENSORFLOW_VERSION=2.16.1 \
    . -t repo/image:tag --push
```
