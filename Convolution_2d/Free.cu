
/* Daniel Diaz Giraldo

Restrictions
Mask = 5, Only works whit odd numbers and Mask size <= N _elements;
N_elements = defined by architecture from machine; (Femin-Maxwell....) in this case
i'm use a Kepler Arch; (the number of blocks that can support is around 2^31)

*/

#include <bits/stdc++.h>
#include <cuda.h>
#include <highgui.h>
#include <cv.h>

#define N_elements 32
#define Mask_size  5
#define TILE_SIZE  1024
#define BLOCK_SIZE 1024

using namespace std;
using namespace cv;


__device__ unsigned char clamp(int value){
    if(value < 0)
        value = 0;
    else
        if(value > 255)
            value = 255;
    return (unsigned char)value;
}



__global__ void convolution2d_global_kernel(unsigned char *In,char *M, unsigned char *Out,int Mask_Width,int Rowimg,int Colimg){

   unsigned int row = blockIdx.y*blockDim.y+threadIdx.y;
   unsigned int col = blockIdx.x*blockDim.x+threadIdx.x;

   int Pvalue = 0;

   int N_start_point_row = row - (Mask_Width/2);
   int N_start_point_col = col - (Mask_Width/2);

   for(int i = 0; i < Mask_Width; i++){
       for(int j = 0; j < Mask_Width; j++ ){
        if((N_start_point_col + j >=0 && N_start_point_col + j < Rowimg)&&(N_start_point_row + i >=0 && N_start_point_row + i < Colimg)){
               Pvalue += In[(N_start_point_row + i)*Rowimg+(N_start_point_col + j)] * M[i*Mask_Width+j];
           }
       }
   }
   Out[row*Rowimg+col] = clamp(Pvalue);

}

//:: Invocation Function

void d_convolution1d(Mat image,unsigned char *In,unsigned char *Out,char *h_Mask,unsigned int Mask_Width,unsigned int Row,unsigned int Col,int op){
  // Variables
  int Size_of_bytes =  sizeof(unsigned char)*Row*Col*image.channels();
  int Mask_size_bytes =  sizeof(char)*9;
  unsigned char *d_In, *d_Out;
  char *d_Mask;
  float Blocksize=BLOCK_SIZE;


  // Memory Allocation in device
  cudaMalloc((void**)&d_In,Size_of_bytes);
  cudaMalloc((void**)&d_Out,Size_of_bytes);
  cudaMalloc((void**)&d_Mask,Mask_size_bytes);
  // Memcpy Host to device
  cudaMemcpy(d_In,In,Size_of_bytes,cudaMemcpyHostToDevice);
  cudaMemcpy(d_Out,Out,Size_of_bytes,cudaMemcpyHostToDevice);
  cudaMemcpy(d_Mask,h_Mask,Mask_size_bytes,cudaMemcpyHostToDevice);
  //cudaMemcpyToSymbol(Global_Mask,h_Mask,Mask_size*sizeof(int)); // avoid cache coherence
  // Thead logic and Kernel call
  dim3 dimGrid(ceil(Row/Blocksize),ceil(Col/Blocksize),1);
  dim3 dimBlock(ceil(Row/Blocksize),ceil(Col/Blocksize),1);
  convolution2d_global_kernel<<<dimGrid,dimBlock>>>(d_In,d_Mask,d_Out,Mask_Width,Row,Col);

  cudaDeviceSynchronize();
  // save output result.
  cudaMemcpy (Out,d_Out,Size_of_bytes,cudaMemcpyDeviceToHost);
  // Free device memory
  cudaFree(d_In);
  cudaFree(d_Out);
  cudaFree(d_Mask);
}



// :::::::::::::::::::::::::::::::::::Clock Function::::::::::::::::::::::::::::
double diffclock(clock_t clock1,clock_t clock2){
  double diffticks=clock2-clock1;
  double diffms=(diffticks)/(CLOCKS_PER_SEC/1); // /1000 mili
  return diffms;
}
// :::::::::::::::::::::::::::::::::::::::Main::::::::::::::::::::::::::::::::::

int main(){

  int Mask_Width =  Mask_size;
  int scale = 1;
  int delta = 0;
  int ddepth = CV_8UC1;
  Mat image;
  image = imread("inputs/img1.jpg",0);   // Read the file

  Size s = image.size();

  int Row = s.width;
  int Col = s.height;

  char h_Mask[] = {-1,0,1,-2,0,2,-1,0,1};
  unsigned char *img = (unsigned char*)malloc(sizeof(unsigned char)*Row*Col*image.channels());
  unsigned char *imgOut = (unsigned char*)malloc(sizeof(unsigned char)*Row*Col*image.channels());

  img = image.data;

  //::::::::::::::::::::::::::::::::::::::::: Secuential filter ::::::::::::::::::::::::::::::::::::

  /// Generate grad_x and grad_y
  //Mat grad_x, grad_y;

  /// Gradient X
  //   ( src  , grad_x, ddepth,dx,dy,scale,delta, BORDER_DEFAULT );
  //Sobel( image, grad_x, ddepth, 1, 0, 3, scale, delta, BORDER_DEFAULT );

  /// Gradient Y
  //Sobel( image, grad_y, ddepth, 0, 1, 3, scale, delta, BORDER_DEFAULT );
  //imwrite("./outputs/1088015148.png",grad_x);

  //::::::::::::::::::::::::::::::::::::::::: Parallel filter ::::::::::::::::::::::::::::::::::::

  d_convolution1d(image,img,imgOut,h_Mask,Mask_Width,Row,Col,1);
  Mat gray_image;
  gray_image.create(Row,Col,CV_8UC1);
  gray_image.data = imgOut;
  imwrite("./outputs/1088015148.png",gray_image);

  free(img);
  free(imgOut);

  return 0;
}
/*
1 - convolution2d tile constant
2 - convolution2d notile noconstant
3 - convolution2d constant tile simple
*/
