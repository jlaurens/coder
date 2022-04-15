#! \usr\bin\env python
'''!latex:
\begin{coder}{Embedded comment}
This is a python function
\end{coder}
'''
def factorial(n):
  '''Compute n!'''
  if n > 1:
    return n * factorial(n-1)
  return 1

if __name__ == "__main__":
  """!latex:
Execute only if run as a script
  """
  print(f'factorial(10)={factorial(10)}')