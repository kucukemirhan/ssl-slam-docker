ARG BASE_IMAGE=ros:noetic

#################################
#   Librealsense Builder Stage  #
#################################
FROM $BASE_IMAGE as librealsense-builder

SHELL ["/bin/bash", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -qq -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    libssl-dev \
    libusb-1.0-0-dev \
    pkg-config \
    libgtk-3-dev \
    libglfw3-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \    
    curl \
    python3 \
    python3-dev \
    ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src

# Use version 2.50.0 explicitly
RUN export LIBRS_VERSION=2.50.0; \
    curl -L https://codeload.github.com/IntelRealSense/librealsense/tar.gz/refs/tags/v${LIBRS_VERSION} -o librealsense.tar.gz; \
    tar -zxf librealsense.tar.gz; \
    rm librealsense.tar.gz; \
    ln -s /usr/src/librealsense-${LIBRS_VERSION} /usr/src/librealsense

RUN cd /usr/src/librealsense \
 && mkdir build && cd build \
 && cmake \
    -DCMAKE_C_FLAGS_RELEASE="${CMAKE_C_FLAGS_RELEASE} -s" \
    -DCMAKE_CXX_FLAGS_RELEASE="${CMAKE_CXX_FLAGS_RELEASE} -s" \
    -DCMAKE_INSTALL_PREFIX=/opt/librealsense \    
    -DBUILD_GRAPHICAL_EXAMPLES=OFF \
    -DBUILD_PYTHON_BINDINGS:bool=true \
    -DCMAKE_BUILD_TYPE=Release ../ \
 && make -j$(($(nproc)-1)) all \
 && make install

######################################
#   librealsense Base Image Stage    #
######################################
FROM ${BASE_IMAGE} as librealsense

SHELL ["/bin/bash", "-c"]

COPY --from=librealsense-builder /opt/librealsense /usr/local/
COPY --from=librealsense-builder /usr/lib/python3/dist-packages/pyrealsense2 /usr/lib/python3/dist-packages/pyrealsense2
COPY --from=librealsense-builder /usr/src/librealsense/config/99-realsense-libusb.rules /etc/udev/rules.d/
ENV PYTHONPATH=${PYTHONPATH}:/usr/local/lib

ENV DEBIAN_FRONTEND=noninteractive

# Install essential tools (build-essential, cmake, git)
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install Ceres Solver
RUN apt-get update && apt-get install -y --no-install-recommends \
    libceres-dev \
    && rm -rf /var/lib/apt/lists/*

# Install PCL
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpcl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install OctoMap
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-noetic-octomap* \
    && rm -rf /var/lib/apt/lists/*

# Preseed tzdata to avoid interactive prompts
RUN echo "tzdata tzdata/Areas select Etc" | debconf-set-selections && \
    echo "tzdata tzdata/Zones/Etc select UTC" | debconf-set-selections

# Install Hector Trajectory Server and tzdata
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-noetic-hector-trajectory-server \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

# Install dependencies required for RealSense and ssl_slam
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-noetic-eigen-conversions \
    ros-noetic-ddynamic-reconfigure \
    ros-noetic-cv-bridge \
    ros-noetic-diagnostic-updater \
    && rm -rf /var/lib/apt/lists/*

# Create a Catkin workspace
RUN mkdir -p /catkin_ws/src
WORKDIR /catkin_ws

# Clone the realsense-ros repository into the workspace's src directory
RUN cd src && git clone https://github.com/IntelRealSense/realsense-ros.git

# Checkout the specified RealSense ROS version
ARG REALSENSE_ROS_VERSION=2.3.2
RUN cd src/realsense-ros && git checkout ${REALSENSE_ROS_VERSION}

# Clone ssl_slam repository into the workspace's src directory
RUN cd src && git clone https://github.com/wh200720041/ssl_slam.git

# Build the workspace
RUN /bin/bash -c "source /opt/ros/noetic/setup.bash && catkin_make clean"
RUN /bin/bash -c "source /opt/ros/noetic/setup.bash && catkin_make -DCATKIN_ENABLE_TESTING=False -DCMAKE_BUILD_TYPE=Release"
RUN /bin/bash -c "source /opt/ros/noetic/setup.bash && catkin_make install"

# Copy entrypoint script into the container and set permissions
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

COPY /scripts/ /catkin_ws/src/

# Source workspace in every new shell session
RUN echo "source /catkin_ws/devel/setup.bash" >> /root/.bashrc

# Use the entrypoint script to automatically source environments
ENTRYPOINT ["/entrypoint.sh"]

RUN apt-get update && apt-get install -y --no-install-recommends \
    gedit \
    && rm -rf /var/lib/apt/lists/*

# Default command: start an interactive shell
CMD ["/bin/bash"]
