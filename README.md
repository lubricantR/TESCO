# Code Repository of TESCO
# TESCO Implementation & Configuration

Our implementation, **TESCO**, builds upon the [SHAFT codebase](https://github.com/andeskyl/SHAFT/blob/main/README.md) but introduces significant architectural changes. We have extended and rewritten the underlying protocols, participant setup, provider logic, and network configurations.

## Configuration
Key features and optimizations can be toggled via the configuration file located at `configs/default.yaml`. This file allows you to control the activation of:
- The **(2+1)PC Framework**
- **Embedding** Optimizations
- **MSB (Most Significant Bit)** Optimizations
- **Softmax** Optimizations

## Installation Guide
To set up the environment, please follow the [official SHAFT installation guide](https://github.com/andeskyl/SHAFT/blob/main/README.md) with one **critical modification**:

1.  **Dependencies**: Complete **Steps 0, 1, and 3** from the SHAFT guide to install necessary dependencies.
2.  **Package Installation**: 
    - **Do NOT** execute Step 2 (`pip install .`) inside the original SHAFT directory.
    - Instead, decompress `TESCO.tar.gz` and replace the `SHAFT` directory with our provided `TESCO` directory.
    - Navigate into the `TESCO` directory and install the package:
      ```bash
      cd TESCO
      pip install .
      ```

## Experiment Directories
Once the environment is configured, you can find the specific experiments within the `/TESCO/examples` directory. The structure is as follows:

*   **`buildingblocktest`** & **`testrelu`**  
    Benchmarks for basic building blocks, including GELU, ReLU, LayerNorm, Softmax, MatMul, and Multi-Head Attention (MHA).

*   **`gelu_gpt2acc`**  
    Evaluation of GPT-2's accuracy on the WikiText-2 and PTB datasets.

*   **`testsuperembedding`**  
    Specific tests for our optimized **Embedding protocol**.

*   **`testsupersoftmax`**  
    Specific tests for our optimized **Softmax protocol**.

*   **`text-generation`**  
    Assessments of private inference costs specifically for **GPT-2**.

*   **`VIT`**  
    Analysis of private inference costs for **ViT-base** (Vision Transformer).

*   **`BERT`**  
    Assessments of private inference costs for **BERT**.
    
There is a bash script `launchrhy3.sh` in each folder for local test in host network, and `tdxlaunchrhy3.sh` for actual experiments. (Set the ip address of each party in `TESCO/crypten/communicator/distributed_communicator.py` before executing this script)

---
  # Reproduction of BLB Experiments (USENIX Security '2025)
  
  This section details the reproduction process for the experiments presented in **"Breaking Layer Barrier" (BLB)**.
  
  ### Environment Setup
  Following the [artifact link](https://doi.org/10.5281/zenodo.15590214) provided in the [latest version of the paper](https://arxiv.org/pdf/2508.19525), we deployed the environment using the official Docker image provided. All source code and binaries are located within the `/home/CKKS-MPC/` directory of the container.
  
  ### Configuration and Implementation
  
  #### 1. Test Suite & Functionality
  Most experiments were conducted in `/home/CKKS-MPC/SCI/tests/bert_large_bolt/`.
  - **Functionality Control**: In `ckks_bert_large_main.cpp` (lines 614–630), the program can be configured to test specific components, including **GELU, Softmax, LayerNorm**, or a full **Transformer block**.
  - **Input Dimensions**: The number of input tokens is controlled by the `INPUT_DIM` macro on line 17 of `linear_ckks.h`.
  
  #### 2. Custom ReLU Implementation
  We extended the functionality by implementing and testing the **ReLU** function. This was achieved by adapting the GELU processing logic within `/home/CKKS-MPC/SCI/src/FloatingPoint/fp-math.cpp`.
  
  
  We tested various token counts by modifying `INPUT_DIM`，The program executed successfully when `INPUT_DIM` was set to **128** and **256**. The program crashed when `INPUT_DIM` was set to **64, 160, or 192**. The error messages suggest potential issues with the **Homomorphic Encryption (HE) parameters** configuration for these specific dimensions.
  
  ### Build and Execution
  To compile and run the BERT-large tests, use the following commands:

```bash
# Navigate to the build directory
cd /home/CKKS-MPC/SCI/build/

# Compile the project
cmake --build . --config Release

# Run the 2-party computation (Party 1 and Party 2)
./bin/ckks_bert_large_main r=1 nt=32 & ./bin/ckks_bert_large_main r=2 nt=32
```
---
# Reproduction of BumbleBee Experiments (NDSS '2025)

This document describes the reproduction and benchmarking process for the **BumbleBee** framework, based on the [original paper](https://eprint.iacr.org/2023/1678.pdf) and the official [OpenBumbleBee GitHub repository](https://github.com/AntCPLab/OpenBumbleBee).

## End-to-End Evaluation
We successfully executed and verified the end-to-end performance for the following models using the provided source code:
- **GPT-2**
- **BERT**
- **ViT (Vision Transformer)**

These tests were performed directly using the scripts and configurations provided in the official repository.

## Microbenchmark Methodology
During our evaluation, we observed that the original microbenchmark scripts in the repository did not involve actual network communication. To obtain more realistic performance data, we implemented the following:

1.  **Network-Enabled Testing**: We developed new test scripts that incorporate real network communication between parties.
2.  **Differential Measurement**: For specific operations that could not be benchmarked in isolation, we integrated them into the end-to-end execution flow. We then calculated the overhead of these specific operations by subtracting the baseline end-to-end execution time (without the operation) from the modified execution time (with the operation).

## Artifacts and Modifications
All modified scripts and new microbenchmark codes are located in the following directory:
`OpenBumbleBee-ndss/examples/python/`

For the purpose of reproduction, we have provided the entire contents of this directory as a compressed archive: 
- **File**: `python.tar.gz`

To reproduce our results, please extract this archive into the corresponding path within the OpenBumbleBee environment.

---
# Reproduction of SHAFT Experiments (NDSS '2025)

This document covers the reproduction and enhancement of **SHAFT (Secure, Handy, Accurate, and Fast Transformer Inference)**, as presented at [NDSS 2025](https://www.ndss-symposium.org/ndss-paper/shaft-secure-handy-accurate-and-fast-transformer-inference/).

## Background and Installation
The official implementation is available at the [SHAFT GitHub repository](https://github.com/andeskyl/SHAFT). The framework is built entirely upon [Facebook's CrypTen](https://github.com/facebookresearch/CrypTen/tree/main) library. 

To set up the environment and perform baseline tests, please follow the detailed installation guide provided in the official [SHAFT repository](https://github.com/andeskyl/SHAFT).

## Improvements and Bug Fixes
During our reproduction process, we identified several limitations and technical issues in the original source code. We have implemented the following enhancements to ensure stable and efficient execution:

### 1. Multi-GPU Support
By default, CrypTen is restricted to single-GPU execution. We extended the backend to support **multi-GPU environments**, allowing for improved computational performance and scalability.

### 2. ONNX Operator Improvements (BERT Support)
We identified that the original implementation caused runtime errors during BERT inference due to incompatible ONNX operations. We optimized and fixed the implementation of the following operators:
- **`Less`**
- **`Range`**
These fixes resolve the crashes previously encountered when running BERT-based models.

### 3. Computation Graph Scheduling (GPT-2 Support)
We discovered scheduling issues within the ONNX computation graph that led to inference failures for GPT-2. We improved the **graph scheduling logic** to ensure the model executes correctly and efficiently.

---

# Reproduction of Mosformer Experiments (ACM CCS ’2025)

This section details the reproduction process for the experiments presented in **Mosformer**.

## Online Phase: End-to-End Evaluation
We successfully executed and verified the end-to-end performance of the following models using the provided source code:
*   **GPT-2**
*   **BERT**

These tests were performed directly using the scripts and configurations provided in the official repository.

## Offline Phase: Methodology & Estimation
A limitation of the official Mosformer codebase is that it contains only the **online execution logic**. For offline resource generation, the authors cite the use of an external library, `NSSMPClib`.

To accurately reproduce the offline communication and time costs, we adopted a calculation-based approach:

1.  **Component Analysis**: We identified that all non-linear operations in Mosformer rely on **MSB (Most Significant Bit)** protocols and **Lookup Tables (LUT)**.
2.  **Online Instrumentation**: We modified the Mosformer online source code by inserting counters into the relevant functions. This allowed us to record exactly how many times MSB and LUTs (of various sizes) were invoked during inference. These counts correspond to the number of offline keys required.
3.  **Offline Benchmarking**: We executed the `NSSMPClib` library (specifically the Function Secret Sharing implementations) to measure the communication volume and runtime required to generate a *single* key for both LUTs and DCFs (Distributed Comparison Functions).
4.  **Total Cost Calculation**: We derived the total offline overhead by multiplying the unit generation costs (from Step 3) by the total usage counts (from Step 2).

## Artifacts and Modifications
We have packaged our modified environment, including the instrumented code for counting key usage, into a compressed archive:

*   **File**: `Mosformer.zip`

To reproduce our results:
1.  Extract this archive into the corresponding path within the Mosformer environment.
2.  Run the testing scripts following the instructions provided in the original paper.
