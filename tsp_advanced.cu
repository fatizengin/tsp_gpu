#include <stdio.h>
#include <stdlib.h>
#include <cuda_runtime.h>
#include <cuda.h>
#include <math.h>
#include <string.h>
#include <limits.h>
#include <assert.h>
#include <unistd.h>
#include <iostream>
#include <fstream>
#include "utils.h"
#include "tsp_solve.h"


#define t_num 1024
#define GRID_SIZE 8192

/*
For more samples define GRID_SIZE as a multiple of t_num such as 512000, 2048000, or the (max - 1024) grid size 2147482623
Some compliation options that can speed things up
--use_fast_math
--optimize=5
--gpu-architecture=compute_35
I use something like
nvcc --optimize=5 --use_fast_math -arch=compute_35 tsp_cuda.cu -o tsp_cuda
*/

int main(){

    const char *tsp_name = "dsj1000.tsp";
     read_tsp(tsp_name);
    unsigned int N = meta -> dim, *N_g;  
    // start counters for cities
    unsigned int i;

    coordinates *location_g;
    

    unsigned int *salesman_route = (unsigned int *)malloc(N * sizeof(unsigned int));

    // just make one inital guess route, a simple linear path
    for (i = 0; i < N; i++)
        salesman_route[i] = i;

    // Set the starting and end points to be the same
    salesman_route[N - 1] = salesman_route[0];

    /*     don't need it when importing data from files
    // initialize the coordinates and sequence
    for(i = 0; i < N; i++){
    location[i].x = rand() % 1000;
    location[i].y = rand() % 1000;
    }
    */

    read_tsp(tsp_name);

    // Calculate the original loss
    float original_loss = 0;
    for (i = 0; i < N - 1; i++){
        original_loss += (location[salesman_route[i]].x - location[salesman_route[i + 1]].x) *
            (location[salesman_route[i]].x - location[salesman_route[i + 1]].x) +
            (location[salesman_route[i]].y - location[salesman_route[i + 1]].y) *
            (location[salesman_route[i]].y - location[salesman_route[i + 1]].y);
    }
    printf("Original Loss is: %.6f \n", original_loss);
    // Keep the original loss for comparison pre/post algorithm
    // FIXME: Changing this to > 5000 causes an error
    float T = 2000.0f, *T_g;
    int *r_g;
    int *r_h = (int *)malloc(GRID_SIZE * sizeof(int));
    for (i = 0; i<GRID_SIZE; i++)
    {
        r_h[i] = rand();
    }
    /*
    Defining device variables:
    city_swap_one_h/g: [integer(t_num)]
    - Host/Device memory for city one
    city_swap_two_h/g: [integer(t_num)]
    - Host/Device memory for city two
    flag_h/g: [integer(t_num)]
    - Host/Device memory for flag of accepted step
    salesman_route_g: [integer(N)]
    - Device memory for the salesmans route
    r_g:  [float(t_num)]
    - Device memory for the random number when deciding acceptance
    flag_h/g: [integer(t_num)]
    - host/device memory for acceptance vector
    original_loss_g: [integer(1)]
    - The device memory for the current loss function
    (DEPRECATED)new_loss_h/g: [integer(t_num)]
    - The host/device memory for the proposal loss function
    */
    unsigned int *city_swap_one_h = (unsigned int *)malloc(GRID_SIZE * sizeof(unsigned int));
    unsigned int *city_swap_two_h = (unsigned int *)malloc(GRID_SIZE * sizeof(unsigned int));
    unsigned int *flag_h = (unsigned int *)malloc(GRID_SIZE * sizeof(unsigned int));
    unsigned int *salesman_route_g, *flag_g, *city_swap_one_g, *city_swap_two_g;
    unsigned int global_flag_h = 0, *global_flag_g;

    cudaMalloc((void**)&city_swap_one_g, GRID_SIZE * sizeof(unsigned int));
    cudaCheckError();
    cudaMalloc((void**)&city_swap_two_g, GRID_SIZE * sizeof(unsigned int));
    cudaCheckError();
    cudaMalloc((void**)&salesman_route_g, N * sizeof(unsigned int));
    cudaCheckError();
    cudaMalloc((void**)&location_g, N * sizeof(coordinates));
    cudaCheckError();
    cudaMalloc((void**)&salesman_route_g, N * sizeof(unsigned int));
    cudaCheckError();
    cudaMalloc((void**)&T_g, sizeof(float));
    cudaCheckError();
    cudaMalloc((void**)&r_g, GRID_SIZE * sizeof(int));
    cudaCheckError();
    cudaMalloc((void**)&flag_g, GRID_SIZE * sizeof(unsigned int));
    cudaCheckError();
    cudaMalloc((void**)&global_flag_g, sizeof(unsigned int));
    cudaCheckError();
    cudaMalloc((void**)&N_g, sizeof(unsigned int));
    cudaCheckError();


    cudaMemcpy(location_g, location, N * sizeof(coordinates), cudaMemcpyHostToDevice);
    cudaCheckError();
    cudaMemcpy(salesman_route_g, salesman_route, N * sizeof(unsigned int), cudaMemcpyHostToDevice);
    cudaCheckError();
    cudaMemcpy(r_g, r_h, GRID_SIZE * sizeof(int), cudaMemcpyHostToDevice);
    cudaCheckError();
    cudaMemcpy(global_flag_g, &global_flag_h, sizeof(unsigned int), cudaMemcpyHostToDevice);
    cudaCheckError();
    cudaMemcpy(N_g, &N, sizeof(unsigned int), cudaMemcpyHostToDevice);
    cudaCheckError();
    // Beta is the decay rate
    //float beta = 0.0001;
    // We are going to try some stuff for temp from this adaptive simulated annealing paper
    // https://arxiv.org/pdf/cs/0001018.pdf

    // Number of thread blocks in grid
    dim3 blocksPerGrid(GRID_SIZE / t_num, 1, 1);
    dim3 threadsPerBlock(t_num, 1, 1);

    //FIXME: Setting this to less than 900 causes an error
    while (T > 1000.0f){
        // Init parameters
        global_flag_h = 0;
        // Copy memory from host to device
        cudaMemcpy(T_g, &T, sizeof(float), cudaMemcpyHostToDevice);
        cudaError_t e = cudaGetLastError();                                 \
            if(e!=cudaSuccess) {
              printf(" Temperature was %.6f on failure\n", T);
            }
        cudaCheckError();
        tsp << <blocksPerGrid, threadsPerBlock, 0 >> >(city_swap_one_g, city_swap_two_g,
                                                       location_g, salesman_route_g,
                                                       T_g, r_g, global_flag_g, N_g);
        cudaCheckError();

        cudaThreadSynchronize();
        //cudaMemcpy(&global_flag_h, global_flag_g, sizeof(unsigned int), cudaMemcpyDeviceToHost);
        T = T*0.9999f;
        //T = 1;
        //printf("%d\n",global_flag_h);
    }

    cudaMemcpy(salesman_route, salesman_route_g, N * sizeof(unsigned int), cudaMemcpyDeviceToHost);
    cudaCheckError();
    float optimized_loss = 0;
    for (i = 0; i < N - 1; i++){
        optimized_loss += (location[salesman_route[i]].x - location[salesman_route[i + 1]].x) *
            (location[salesman_route[i]].x - location[salesman_route[i + 1]].x) +
            (location[salesman_route[i]].y - location[salesman_route[i + 1]].y) *
            (location[salesman_route[i]].y - location[salesman_route[i + 1]].y);
    }
        printf("Optimized Loss is: %.6f \n", optimized_loss);
    
    /*
    printf("\n Final Route:\n");
    for (i = 0; i < N; i++)
    printf("%d ",salesman_route[i]);
    */
    cudaFree(location_g);
    cudaCheckError();
    cudaFree(salesman_route_g);
    cudaCheckError();
    cudaFree(T_g);
    cudaCheckError();
    cudaFree(r_g);
    cudaCheckError();
    cudaFree(flag_g);
    cudaCheckError();
    free(salesman_route);
    free(city_swap_one_h);
    free(city_swap_two_h);
    free(flag_h);
    free(location);
    return 0;
}
