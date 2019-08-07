# UnsignedHexaCalc
The operations supported by your calculator
'q' – quit
'+' – unsigned addition (pop two operands from operand stack, and push one result, their sum)
'p' – pop-and-print (pop one operand from the operand stack, and print its value to stdout)
'd' – duplicate (push a copy of the top of the operand stack onto the top of the operand stack)
'^' - X*2^Y, with X being the top of operand stack and Y the element next to x in the operand stack. If Y>200 this is considered an error.
'v' – X*2^(-Y), with X and Y as above.
'n' – number of '1' bits (pop one operand from the operand stack, and push one result)
'sr' – square root (pop one operand from the operand stack, and push one result)
