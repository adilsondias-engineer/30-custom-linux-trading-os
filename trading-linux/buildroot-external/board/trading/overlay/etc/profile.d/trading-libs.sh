#!/bin/sh
# Set library paths for trading system
# This file is sourced by all shell sessions

# Add CUDA and XGBoost libraries to LD_LIBRARY_PATH
export LD_LIBRARY_PATH="/opt/cuda/lib64:/opt/xgboost/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Add CUDA binaries to PATH
export PATH="/opt/cuda/bin${PATH:+:$PATH}"

