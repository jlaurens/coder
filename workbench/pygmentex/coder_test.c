/*!latex:
\begin{coder}{Embedded comment}
This is a C function.
\end{coder}
*/
#include <stdio.h>
int factorial(int n);
int factorial(n) {
  if (n > 1) {
    return n * factorial(n-1);
  }
  return 1;
}
int main(int argc, char **argv) {
  printf("factorial(10)=%d",factorial(10));
  return 0;
}
