# Build stage
FROM nvidia/cuda:12.1.0-devel-ubuntu22.04 as builder

RUN apt-get update -y \
    && apt-get install -y python3-pip python3-dev git \
    && rm -rf /var/lib/apt/lists/*

RUN ldconfig /usr/local/cuda-12.1/compat/

# Install Python dependencies
COPY builder/requirements.txt /requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip \
    python3 -m pip install --upgrade pip && \
    python3 -m pip install --upgrade -r /requirements.txt

# Install vLLM from source at specific commit
RUN git clone https://github.com/vllm-project/vllm.git && \
    cd vllm && \
    git checkout f3a507f1d31e13a99c4fc8ac02738a73c3e3136f && \
    pip install -e . && \
    cd .. && \
    rm -rf vllm

# Install FlashInfer
RUN python3 -m pip install flashinfer -i https://flashinfer.ai/whl/cu121/torch2.3

# Production stage
FROM nvidia/cuda:12.1.0-base-ubuntu22.04

# Copy Python and installed packages from builder
COPY --from=builder /usr/local /usr/local
COPY --from=builder /usr/lib /usr/lib

RUN ldconfig /usr/local/cuda-12.1/compat/

# Install runtime dependencies
RUN apt-get update -y \
    && apt-get install -y python3 libpython3.10 \
    && rm -rf /var/lib/apt/lists/*

# Setup for Option 2: Building the Image with the Model included
ARG MODEL_NAME=""
ARG TOKENIZER_NAME=""
ARG BASE_PATH="/runpod-volume"
ARG QUANTIZATION=""
ARG MODEL_REVISION=""
ARG TOKENIZER_REVISION=""

ENV MODEL_NAME=$MODEL_NAME \
    MODEL_REVISION=$MODEL_REVISION \
    TOKENIZER_NAME=$TOKENIZER_NAME \
    TOKENIZER_REVISION=$TOKENIZER_REVISION \
    BASE_PATH=$BASE_PATH \
    QUANTIZATION=$QUANTIZATION \
    HF_DATASETS_CACHE="${BASE_PATH}/huggingface-cache/datasets" \
    HUGGINGFACE_HUB_CACHE="${BASE_PATH}/huggingface-cache/hub" \
    HF_HOME="${BASE_PATH}/huggingface-cache/hub" \
    HF_HUB_ENABLE_HF_TRANSFER=1 

ENV PYTHONPATH="/:/vllm-workspace"

COPY src /src
RUN --mount=type=secret,id=HF_TOKEN,required=false \
    if [ -f /run/secrets/HF_TOKEN ]; then \
        export HF_TOKEN=$(cat /run/secrets/HF_TOKEN); \
    fi && \
    if [ -n "$MODEL_NAME" ]; then \
        python3 /src/download_model.py; \
    fi

# Start the handler
CMD ["python3", "/src/handler.py"]