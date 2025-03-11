#!/bin/bash
# Source the ROS environment and your workspace environment
source /opt/ros/noetic/setup.bash
source /catkin_ws/devel/setup.bash

# Execute any passed command or launch an interactive shell
exec "$@"
