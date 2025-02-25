FROM nvidia/cuda:11.2.2-devel-ubuntu18.04

# TensorFlow version is tightly coupled to CUDA and cuDNN so it should be selected carefully
ENV TENSORFLOW_VERSION=2.4.1
ENV PYTORCH_VERSION=1.8.1
ENV PYTORCH_LIGHTNING_VERSION=1.2.9
ENV TORCHVISION_VERSION=0.9.1
ENV CUDNN_VERSION=8.1.1.33-1+cuda11.2
ENV NCCL_VERSION=2.8.4-1+cuda11.2
ENV MXNET_VERSION=1.8.0.post0

ENV PYSPARK_PACKAGE=pyspark==3.1.1
ENV SPARK_PACKAGE=spark-3.1.1/spark-3.1.1-bin-hadoop2.7.tgz

# Python 3.7 is supported by Ubuntu Bionic out of the box
ARG python=3.8
ENV PYTHON_VERSION=${python}

# Set default shell to /bin/bash
SHELL ["/bin/bash", "-cu"]

RUN apt-get update && apt-get install -y --allow-downgrades --allow-change-held-packages --no-install-recommends \
        build-essential \
        cmake \
        g++-7 \
        git \
        curl \
        vim \
        wget \
        ca-certificates \
        libcudnn8=${CUDNN_VERSION} \
        libnccl2=${NCCL_VERSION} \
        libnccl-dev=${NCCL_VERSION} \
        libjpeg-dev \
        libpng-dev \
        python${PYTHON_VERSION} \
        python${PYTHON_VERSION}-dev \
        python${PYTHON_VERSION}-distutils \
        librdmacm1 \
        libibverbs1 \
        ibverbs-providers

RUN ln -s /usr/bin/python${PYTHON_VERSION} /usr/bin/python

RUN curl -O https://bootstrap.pypa.io/get-pip.py && \
    python get-pip.py && \
    rm get-pip.py

# Install TensorFlow, Keras, PyTorch and MXNet
RUN pip install future typing packaging
RUN pip install tensorflow==${TENSORFLOW_VERSION} \
                keras \
                h5py

RUN PYTAGS=$(python -c "from packaging import tags; tag = list(tags.sys_tags())[0]; print(f'{tag.interpreter}-{tag.abi}')") && \
    pip install https://download.pytorch.org/whl/cu111/torch-${PYTORCH_VERSION}%2Bcu111-${PYTAGS}-linux_x86_64.whl \
        https://download.pytorch.org/whl/cu111/torchvision-${TORCHVISION_VERSION}%2Bcu111-${PYTAGS}-linux_x86_64.whl
RUN pip install pytorch_lightning==${PYTORCH_LIGHTNING_VERSION}
RUN pip install mxnet-cu112==${MXNET_VERSION}

# Install Spark stand-alone cluster.
RUN wget --progress=dot:giga "https://www.apache.org/dyn/closer.lua/spark/${SPARK_PACKAGE}?action=download" -O - | tar -xzC /tmp; \
    archive=$(basename "${SPARK_PACKAGE}") bash -c "mv -v /tmp/\${archive/%.tgz/} /spark"

# Install PySpark.
RUN apt-get update -qq && apt install -y openjdk-8-jdk-headless
RUN pip install ${PYSPARK_PACKAGE}

# Install Open MPI
RUN mkdir /tmp/openmpi && \
    cd /tmp/openmpi && \
    wget https://www.open-mpi.org/software/ompi/v4.0/downloads/openmpi-4.0.0.tar.gz && \
    tar zxf openmpi-4.0.0.tar.gz && \
    cd openmpi-4.0.0 && \
    ./configure --enable-orterun-prefix-by-default && \
    make -j $(nproc) all && \
    make install && \
    ldconfig && \
    rm -rf /tmp/openmpi

# Install Horovod, temporarily using CUDA stubs
RUN ldconfig /usr/local/cuda/targets/x86_64-linux/lib/stubs && \
    HOROVOD_GPU_OPERATIONS=NCCL HOROVOD_WITH_TENSORFLOW=1 HOROVOD_WITH_PYTORCH=1 HOROVOD_WITH_MXNET=1 \
         pip install --no-cache-dir horovod[all-frameworks] && \
    ldconfig

# Install OpenSSH for MPI to communicate between containers
RUN apt-get install -y --no-install-recommends openssh-client openssh-server && \
    mkdir -p /var/run/sshd

# Allow OpenSSH to talk to containers without asking for confirmation
RUN cat /etc/ssh/ssh_config | grep -v StrictHostKeyChecking > /etc/ssh/ssh_config.new && \
    echo "    StrictHostKeyChecking no" >> /etc/ssh/ssh_config.new && \
    mv /etc/ssh/ssh_config.new /etc/ssh/ssh_config

# # Download examples
# RUN apt-get install -y --no-install-recommends subversion && \
#     svn checkout https://github.com/horovod/horovod/trunk/examples && \
#     rm -rf /examples/.svn

# WORKDIR "/examples"

RUN mkdir -p /workspace
WORKDIR /workspace

# # install python packages: for requirements.txt, uncomment the next two
# COPY requirements.txt /workspace/
# RUN pip install -r requirements.txt
