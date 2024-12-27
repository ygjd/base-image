# Building

This Dockerfile relies on the structure provided by [Vast.Ai Base images](https://github.com/vast-ai/base-image).

See the example below for building instructions.

```bash
docker buildx build \
    --platform linux/amd64 \
    --build-arg BASE_IMAGE=vastai/base-image:cuda-12.4.1-cudnn-devel-ubuntu22.04 \
    --build-arg PIXEL_STREAMING_REF=UE5.5-4.0.6 \
    -t repo/image:tag --push
```
