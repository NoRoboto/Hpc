#include <bits/stdc++.h>
#include <cuda.h>
#include <highgui.h>
#include <cv.h>

#define Mask_size 3
//#define TILE_size_of_rgb  1024
#define BLOCKSIZE 32
#define TILE_SIZE 32

const int TILE_WIDTH	= 16;
const int TILE_HEIGHT	= 16;
const int FILTER_RADIUS = 3; //  3 for averge, 1 for sobel
const int FILTER_AREA	= (2*FILTER_RADIUS+1) * (2*FILTER_RADIUS+1);
const int BLOCK_WIDTH	= TILE_WIDTH + 2 * FILTER_RADIUS;
const int BLOCK_HEIGHT	= TILE_HEIGHT + 2 * FILTER_RADIUS;

using namespace std;
using namespace cv;

__constant__ char Global_Mask[Mask_size*Mask_size];

__device__ unsigned char clamp(int value){
    if(value < 0)
        value = 0;
    else
        if(value > 255)
            value = 255;
    return  value;
}

__global__ void sobelFilter(unsigned char *In, int Row, int Col, unsigned int Mask_Width,char *Mask,unsigned char *Out){
    unsigned int row = blockIdx.y*blockDim.y+threadIdx.y;
    unsigned int col = blockIdx.x*blockDim.x+threadIdx.x;
    int Pvalue = 0;
    int N_start_point_row = row - (Mask_Width/2);
    int N_start_point_col = col - (Mask_Width/2);

    for(int i = 0; i < Mask_Width; i++){
        for(int j = 0; j < Mask_Width; j++ ){
            if((N_start_point_col + j >=0 && N_start_point_col + j < Row)&&(N_start_point_row + i >=0 && N_start_point_row + i < Col)){
                Pvalue += In[(N_start_point_row + i)*Row+(N_start_point_col + j)] * Mask[i*Mask_Width+j];
            }
        }
    }
    Out[row*Row+col] = clamp(Pvalue);
}


__global__ void sobelFilterConstant(unsigned char *In, int Row, int Col, unsigned int Mask_Width,char *Mask,unsigned char *Out){
    unsigned int row = blockIdx.y*blockDim.y+threadIdx.y;
    unsigned int col = blockIdx.x*blockDim.x+threadIdx.x;
    int Pvalue = 0;
    int N_start_point_row = row - (Mask_Width/2);
    int N_start_point_col = col - (Mask_Width/2);

    for(int i = 0; i < Mask_Width; i++){
        for(int j = 0; j < Mask_Width; j++ ){
            if((N_start_point_col + j >=0 && N_start_point_col + j < Row)&&(N_start_point_row + i >=0 && N_start_point_row + i < Col)){
                Pvalue += In[(N_start_point_row + i)*Row+(N_start_point_col + j)] * Mask[i*Mask_Width+j];
            }
        }
    }
    Out[row*Row+col] = clamp(Pvalue);
}


__global__ void sobelFilterShared(unsigned char *data, unsigned char *result, int width, int height){
  // Data cache: threadIdx.x , threadIdx.y
  const int n = Mask_size / 2;
  __shared__ int s_data[BLOCKSIZE + Mask_size * 2 ][BLOCKSIZE + Mask_size * 2];

  // global mem address of the current thread in the whole grid
  const int pos = threadIdx.x + blockIdx.x * blockDim.x + threadIdx.y * width + blockIdx.y * blockDim.y * width;

  // load cache (32x32 shared memory, 16x16 threads blocks)
  // each threads loads four values from global memory into shared mem
  // if in image area, get value in global mem, else 0
  int x, y; // image based coordinate

  // original image based coordinate
  const int x0 = threadIdx.x + blockIdx.x * blockDim.x;
  const int y0 = threadIdx.y + blockIdx.y * blockDim.y;

  // case1: upper left
  x = x0 - n;
  y = y0 - n;
  if ( x < 0 || y < 0 )
    s_data[threadIdx.y][threadIdx.x] = 0;
  else
    s_data[threadIdx.y][threadIdx.x] = *(data + pos - n - (width * n));

  // case2: upper right
  x = x0 + n;
  y = y0 - n;
  if ( x > (width - 1) || y < 0 )
    s_data[threadIdx.y][threadIdx.x + blockDim.x] = 0;
  else
    s_data[threadIdx.y][threadIdx.x + blockDim.x] = *(data + pos + n - (width * n));

  // case3: lower left
  x = x0 - n;
  y = y0 + n;
  if (x < 0 || y > (height - 1))
    s_data[threadIdx.y + blockDim.y][threadIdx.x] = 0;
  else
    s_data[threadIdx.y + blockDim.y][threadIdx.x] = *(data + pos - n + (width * n));

  // case4: lower right
  x = x0 + n;
  y = y0 + n;
  if ( x > (width - 1) || y > (height - 1))
    s_data[threadIdx.y + blockDim.y][threadIdx.x + blockDim.x] = 0;
  else
    s_data[threadIdx.y + blockDim.y][threadIdx.x + blockDim.x] = *(data + pos + n + (width * n));

  __syncthreads();

  // convolution
  int sum = 0;
  x = n + threadIdx.x;
  y = n + threadIdx.y;
  for (int i = - n; i <= n; i++)
    for (int j = - n; j <= n; j++)
      sum += s_data[y + i][x + j] * Global_Mask[n + i] * Global_Mask[n + j];

  result[pos] = sum;
}


__global__ void sobelFilterShared2(unsigned char *data, unsigned char *result, int width, int height){
  // Data cache: threadIdx.x , threadIdx.y
  int ty = threadIdx.y;
  int tx = threadIdx.x;

  // shared memory represented here by 1D array
  // each thread loads two values from global memory into shared mem
  const int n = Mask_size / 2;
  __shared__ int s_data[BLOCKSIZE * (BLOCKSIZE + Mask_size * 2)];

  // global mem address of the current thread in the whole grid
  const int pos = tx + blockIdx.x * blockDim.x + ty * width + blockIdx.y * blockDim.y * width;

  // load cache (32x32 shared memory, 16x16 threads blocks)
  // each threads loads four values from global memory into shared mem
  // if in image area, get value in global mem, else 0
  int y; // image based coordinate

  // original image based coordinate
  const int y0 = ty + blockIdx.y * blockDim.y;
  const int shift = ty * (BLOCKSIZE);

  // case1: upper left
  y = y0 - n;
  if ( y < 0 )
    s_data[tx + shift] = 0;
  else
    s_data[tx + shift] = data[ pos - (width * n)];

  // case2: lower
  y = y0 - n;
  const int shift1 = shift + blockDim.y * BLOCKSIZE;

  if ( y > height - 1)
    s_data[tx + shift1] = 0;
  else
    s_data[tx + shift1] = data[pos +  (width * n)];

  __syncthreads();

  // convolution
  int sum = 0;
    for (int i = 0; i <= n*2; i++)
      sum += s_data[tx + (ty+i) * BLOCKSIZE] * Global_Mask[i];

  result[pos] = sum;
}

__global__ void sobelFilterShared3(unsigned char* g_DataIn, unsigned char * g_DataOut, unsigned int width, unsigned int height){
  	__shared__ char sharedMem[BLOCK_HEIGHT*BLOCK_WIDTH];

  	int x = blockIdx.x * TILE_WIDTH + threadIdx.x - FILTER_RADIUS;
  	int y = blockIdx.y * TILE_HEIGHT + threadIdx.y - FILTER_RADIUS;

  	//Clamp to the center
  	x = max(FILTER_RADIUS, x);
  	x = min(x, width - FILTER_RADIUS - 1);
  	y = max(FILTER_RADIUS, y);
  	y = min(y, height - FILTER_RADIUS - 1);

  	unsigned int index = y * width + x;
  	unsigned int sharedIndex = threadIdx.y * blockDim.y + threadIdx.x;

  	sharedMem[sharedIndex] = g_DataIn[index];

  	__syncthreads();

  	if(		threadIdx.x >= FILTER_RADIUS && threadIdx.x < BLOCK_WIDTH - FILTER_RADIUS
  		&&	threadIdx.y >= FILTER_RADIUS && threadIdx.y < BLOCK_HEIGHT - FILTER_RADIUS)
  	{
  		int sum = 0;

  		for(int dy = -FILTER_RADIUS; dy <= FILTER_RADIUS; ++dy)
  		for(int dx = -FILTER_RADIUS; dx <= FILTER_RADIUS; ++dx)
  		{
  			int pixelValue = (int)(sharedMem[sharedIndex + (dy * blockDim.x + dx)]);

  			sum += pixelValue;
  		}

  		g_DataOut[index] = (unsigned char)(sum / FILTER_AREA);
  	}
}

__global__ void sobelFilterShared4(unsigned char *In, unsigned char *Out,int maskWidth, int width, int height){
  __shared__ float N_ds[TILE_SIZE + Mask_size - 1][TILE_SIZE+ Mask_size - 1];
   int n = Mask_size/2;
   int dest = threadIdx.y*TILE_SIZE+threadIdx.x, destY = dest / (TILE_SIZE+Mask_size-1), destX = dest % (TILE_SIZE+Mask_size-1),
       srcY = blockIdx.y * TILE_SIZE + destY - n, srcX = blockIdx.x * TILE_SIZE + destX - n,
       src = (srcY * width + srcX);
   if (srcY >= 0 && srcY < height && srcX >= 0 && srcX < width)
       N_ds[destY][destX] = In[src];
   else
       N_ds[destY][destX] = 0;

   // Second batch loading
   dest = threadIdx.y * TILE_SIZE + threadIdx.x + TILE_SIZE * TILE_SIZE;
   destY = dest /(TILE_SIZE + Mask_size - 1), destX = dest % (TILE_SIZE + Mask_size - 1);
   srcY = blockIdx.y * TILE_SIZE + destY - n;
   srcX = blockIdx.x * TILE_SIZE + destX - n;
   src = (srcY * width + srcX);
   if (destY < TILE_SIZE + Mask_size - 1) {
       if (srcY >= 0 && srcY < height && srcX >= 0 && srcX < width)
           N_ds[destY][destX] = In[src];
       else
           N_ds[destY][destX] = 0;
   }
   __syncthreads();

   int accum = 0;
   int y, x;
   for (y = 0; y < maskWidth; y++)
       for (x = 0; x < maskWidth; x++)
           accum += N_ds[threadIdx.y + y][threadIdx.x + x] * Global_Mask[y * maskWidth + x];
   y = blockIdx.y * TILE_SIZE + threadIdx.y;
   x = blockIdx.x * TILE_SIZE + threadIdx.x;
   if (y < height && x < width)
       Out[(y * width + x)] = clamp(accum);
   __syncthreads();
}


__global__ void gray(unsigned char *In, unsigned char *Out,int Row, int Col){
    int row = blockIdx.y*blockDim.y+threadIdx.y;
    int col = blockIdx.x*blockDim.x+threadIdx.x;

    if((row < Col) && (col < Row)){
        Out[row*Row+col] = In[(row*Row+col)*3+2]*0.299 + In[(row*Row+col)*3+1]*0.587+ In[(row*Row+col)*3]*0.114;
    }
}


// :::::::::::::::::::::::::::::::::::Clock Function::::::::::::::::::::::::::::
double diffclock(clock_t clock1,clock_t clock2){
  double diffticks=clock2-clock1;
  double diffms=(diffticks)/(CLOCKS_PER_SEC/1); // /1000 mili
  return diffms;
}

void d_convolution2d(Mat image,unsigned char *In,unsigned char *h_Out,char *h_Mask,int Mask_Width,int Row,int Col,int op){
  // Variables
  int size_of_rgb = sizeof(unsigned char)*Row*Col*image.channels();
  int size_of_Gray = sizeof(unsigned char)*Row*Col; // sin canales alternativos
  int Mask_size_of_bytes =  sizeof(char)*(Mask_size*Mask_size);
  unsigned char *d_In,*d_Out,*d_sobelOut;
  char *d_Mask;
  float Blocksize=BLOCKSIZE;

  // Memory Allocation in device
  cudaMalloc((void**)&d_In,size_of_rgb);
  cudaMalloc((void**)&d_Out,size_of_Gray);
  cudaMalloc((void**)&d_Mask,Mask_size_of_bytes);
  cudaMalloc((void**)&d_sobelOut,size_of_Gray);

  // Memcpy Host to device
  cudaMemcpy(d_In,In,size_of_rgb, cudaMemcpyHostToDevice);
  cudaMemcpy(d_Mask,h_Mask,Mask_size_of_bytes,cudaMemcpyHostToDevice);
  cudaMemcpyToSymbol(Global_Mask,h_Mask,Mask_size_of_bytes); // avoid cache coherence
  // Thread logic and Kernel call
  dim3 dimGrid(ceil(Row/Blocksize),ceil(Col/Blocksize),1);
  dim3 dimBlock(Blocksize,Blocksize,1);
  gray<<<dimGrid,dimBlock>>>(d_In,d_Out,Row,Col); // pasando a escala de grices.
  cudaDeviceSynchronize();
  if(op==1){
    sobelFilter<<<dimGrid,dimBlock>>>(d_Out,Row,Col,Mask_size,d_Mask,d_sobelOut);
  }
  if(op==2){
    sobelFilterConstant<<<dimGrid,dimBlock>>>(d_Out,Row,Col,Mask_size,d_Mask,d_sobelOut);

  }
  if(op==3){
    sobelFilterShared4<<<dimGrid,dimBlock>>>(d_Out,d_sobelOut,3,Row,Col);
  }
  // save output result.
  cudaMemcpy (h_Out,d_sobelOut,size_of_Gray,cudaMemcpyDeviceToHost);
  // Free device memory
  cudaFree(d_In);
  cudaFree(d_Out);
  cudaFree(d_Mask);
  cudaFree(d_sobelOut);
}


int main(){

    double T1,T2; // Time flags
    clock_t start,end;// Time flags

    int Mask_Width = Mask_size;
    char h_Mask[] = {-1,0,1,-2,0,2,-1,0,1};
    Mat image,result_image;
    image = imread("inputs/img1.jpg",1);
    Size s = image.size();
    int Row = s.width;
    int Col = s.height;
    unsigned char * In = (unsigned char*)malloc( sizeof(unsigned char)*Row*Col*image.channels());
    unsigned char * h_Out = (unsigned char *)malloc( sizeof(unsigned char)*Row*Col);

    In = image.data;
    start = clock();
    d_convolution2d(image,In,h_Out,h_Mask,Mask_Width,Row,Col,3);
    end = clock();
    T1=diffclock(start,end);
    cout<<" Result Parallel"<<" At "<<T1<<",Seconds"<<endl;

    Mat gray_image_opencv, grad_x, abs_grad_x;
    start = clock();
    cvtColor(image, gray_image_opencv, CV_BGR2GRAY);
    Sobel(gray_image_opencv,grad_x,CV_8UC1,1,0,3,1,0,BORDER_DEFAULT);
    convertScaleAbs(grad_x, abs_grad_x);
    end = clock();
    T2=diffclock(start,end);
    cout<<" Result secuential"<<" At "<<T2<<",Seconds"<<endl;
    cout<<"Total acceleration "<<T2/T1<<"X"<<endl;

    result_image.create(Col,Row,CV_8UC1);
    result_image.data = h_Out;
    imwrite("./outputs/1088015148.png",result_image);

    return 0;
}
