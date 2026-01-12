# TESCO
code repository of TESCO



  # Reproduction of BLB Experiments (USENIX Security '25)
  
  This section details the reproduction process for the experiments presented in **"Breaking Layer Barrier" (BLB)**.
  
  ## Environment Setup
  Following the [artifact link](https://doi.org/10.5281/zenodo.15590214) provided in the [latest version of the paper](https://arxiv.org/pdf/2508.19525), we deployed the environment using the official Docker image provided. All source code and binaries are located within the `/home/CKKS-MPC/` directory of the container.
  
  ## Configuration and Implementation
  
  ### 1. Test Suite & Functionality
  Most experiments were conducted in `/home/CKKS-MPC/SCI/tests/bert_large_bolt/`.
  - **Functionality Control**: In `ckks_bert_large_main.cpp` (lines 614–630), the program can be configured to test specific components, including **GELU, Softmax, LayerNorm**, or a full **Transformer block**.
  - **Input Dimensions**: The number of input tokens is controlled by the `INPUT_DIM` macro on line 17 of `linear_ckks.h`.
  
  ### 2. Custom ReLU Implementation
  We extended the functionality by implementing and testing the **ReLU** function. This was achieved by adapting the GELU processing logic within `/home/CKKS-MPC/SCI/src/FloatingPoint/fp-math.cpp`.
  
  
  We tested various token counts by modifying `INPUT_DIM`，The program executed successfully when `INPUT_DIM` was set to **128** and **256**. The program crashed when `INPUT_DIM` was set to **64, 160, or 192**. The error messages suggest potential issues with the **Homomorphic Encryption (HE) parameters** configuration for these specific dimensions.
  
  ## Build and Execution
  To compile and run the BERT-large tests, use the following commands:

```bash
# Navigate to the build directory
cd /home/CKKS-MPC/SCI/build/

# Compile the project
cmake --build . --config Release

# Run the 2-party computation (Party 1 and Party 2)
./bin/ckks_bert_large_main r=1 nt=32 & ./bin/ckks_bert_large_main r=2 nt=32
```
d
