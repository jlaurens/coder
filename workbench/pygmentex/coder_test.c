/*!latex:
\begin{coder}{Embedded comment}
This is a C program to compute 10!.
\end{coder}
*/
#include <stdio.h>
int main(int argc, char **argv) {
  int factorial = 1;
  for (int i=2;i<=10;i++) {
    factorial *= i;
  }
  printf("factorial(10)=%d\n",factorial);
  return 0;
}
