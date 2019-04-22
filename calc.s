STACK_SIZE equ 5
INPUT_SIZE equ 80
ASCII equ 48

STDIN equ 0
STDOUT equ 1

SYS_READ equ 0x03
SYS_WRITE equ 0x04
SYS_EXIT equ 0x01

;Works?

%macro errorPrompt 1
	pushad
	push dword %1
	call printf
	add esp, 4
  jmp quit
  popad
%endmacro

%macro checkBuffer 1
  mov ebx, 0
	mov ecx, %1
  mov bl, [buffer + ecx]
  cmp bl, '0'
  jge %%above0
  errorPrompt invalidInput  ;less than 0
  %%above0:  ;it can be digit or capital letter
    cmp bl, '9'
    jle %%endcheckBuffer  ;it's a number
    cmp bl, 'A'  ;now it can be somewhere between 9 and A, or above A
    jge %%aboveA
    errorPrompt invalidInput
  %%aboveA:
    cmp bl, 'F'
    jle %%endcheckBuffer
    errorPrompt invalidInput  ;it's somewhere above F, not hexadecimal!
  %%endcheckBuffer:
%endmacro

%macro checkStackOverflow 0
  mov eax, 0
  mov eax, [stackPointer]
  cmp eax, STACK_SIZE
  jl %%endcheckStackOverflow
  errorPrompt stackOverflow
  %%endcheckStackOverflow:
%endmacro

%macro checkStackUnderflow 1  ;argument is how much operands needed (pop needs 1, plus needs 2)
  mov eax, 0
  mov eax, [stackPointer]
  cmp eax, %1
  jge %%endcheckStackUnderflow
  errorPrompt stackUnderflow
  %%endcheckStackUnderflow:
%endmacro

%macro hexatoBinary 1
	mov dl, 0
	mov dl, [buffer+%1]
	cmp byte dl, 65
	jge %%char
	sub byte dl, ASCII
	jmp %%endhexatoBinary
	%%char:
		sub byte dl, 55
	%%endhexatoBinary:
%endmacro

%macro binarytoHexaChars 0  ;in dl the byte to be converted (edx clean), 4 bits per digit, result in ecx
	mov eax, 0
	mov eax, edx
	shr eax, 4
	cmp eax, 9
	jle %%number
	add eax, 55
	jmp %%second
	%%number:
		add eax, ASCII
	%%second:
		shl eax, 24
		mov ecx, 0  ;will store the result
		mov ecx, eax
		mov eax, 0
		shl dl, 4 ;keep the 4 bits of the second digits
		shr dl, 4
		mov eax, edx
		cmp eax, 9
		jle %%secondisnumber
		add eax, 55
		jmp %%endbinarytoHexaChars
	%%secondisnumber:
		add eax, ASCII
	%%endbinarytoHexaChars:
		shl eax, 16  ;to the left, near the first char
		or ecx, eax  ;keep 2 chars
%endmacro

%macro popOperand 0
	deb2:
	mov eax, [currentNode]  ;maybe problematic cleaning the current node, maybe it's not the last node
	push eax ;the parameter is address of the memory
	call free
	mov eax, [stackPointer]
	sub eax, 1
	mov [stackPointer], eax
%endmacro

section .bss
  operandStack: resb STACK_SIZE*4  ;each element is pointer (4 bytes) to node
  buffer: resb INPUT_SIZE

section .rodata
  calcPrompt: db "calc: ",0
  invalidInput: db "Error: Invalid Input!",10,0
  stackOverflow: db "Error: Operand Stack Overflow",10,0
  stackUnderflow: db "Error: Insufficient Number of Arguments on Stack",10,0

section .data
  stackPointer: dd 0
  previousNode: dd 0  ;contains address of the node
  currentNode: dd 0  ;pointer to the node, holds the address to where the node start
	inputLength: dd 0

section .text
align 16
 global main
 extern printf  ;use when there is '\n' at the end
 extern fflush
 extern malloc
 extern calloc
 extern free
 ;extern gets
 ;extern fgets ;im using system call SYS_READ

main:
	mov eax, 0
	mov ebx, 0
	mov ecx, 0
	mov edx, 0
  mov eax, SYS_WRITE
  mov	ebx, STDOUT		;file descriptor
  mov ecx, calcPrompt
  mov	edx, 7	;message length
  int	0x80		;call kernel

  mov dword eax, SYS_READ
  mov dword ebx, STDIN
  mov dword ecx, buffer
  mov dword edx, INPUT_SIZE
  int 0x80

  cmp byte [buffer], 'q'
  je quit
  cmp byte [buffer], '+'
  je plus
  cmp byte [buffer], 'p'
  je popAndPrint
  cmp byte [buffer], 'd'
  je duplicate
  cmp byte [buffer], '^'
  je power
  cmp byte [buffer], 'v'
  je powerMinus
  cmp byte [buffer], 'n'
  je numOf1Bits
  cmp word [buffer], 'sr'
  je squareRoot
  ;it's none of the above, so it's operand
	checkStackOverflow
  mov ecx, 0  ;stores input length
checkBufferLoop:
	mov bl, 0
  mov bl, [buffer+ecx]
  cmp byte bl, 10   ;10 is ascii of '\n'
  je endOfInput
  checkBuffer ecx
  add ecx, 1
	cmp ecx, eax  ;eax holds the return value of sys_read, = how many bytes read
  jle checkBufferLoop
	;we can assume the input is not empty line, so ecx > 0
endOfInput: ;the buffer is valid
  ;we start from the end, build node from 2 bytes
  ;than connect the current node to the previous
  ;in that way, the digits at the start will be in the first node
  ;last node needs to be in previous node
	mov dword [inputLength], ecx
createNode:
  cmp ecx, 0
  jg .twobytesfrombuffer
  ;special case where we need to add zero bytes to the left
  ;and than continue to the 2bytesbuffer as usual
  .twobytesfrombuffer:
		pushad
    push 5
    call malloc  ;after this, eax holds the pointer to the block of memory, representing one node
    mov dword [currentNode], eax
		pop eax
		popad
    ;moving the 2 digits to the byte in the currentNode
		hexatoBinary ecx ;after this, in dl the trasformed ASCII, the right 4 bytes
		mov bl, 0
		mov bl, dl
		sub ecx, 1
		hexatoBinary ecx
		shl bl, 4
		or bl, dl  ;now the 2 digits are connected
		sub ecx, 1
		mov eax, [currentNode]
		mov byte [eax], bl
	.connect:
		mov ebx,0
		mov ebx, [previousNode]  ;in ebx, the address of the previous node
		mov eax, [currentNode]
  	mov dword [eax+1], ebx  ;connect the current node to the previous
  cmp ecx, 0
  jg createNode
;end of creating nodes, push it to operand stack
  mov eax, [stackPointer]
  mov ebx, [currentNode]  ;pointer to the fist node
  mov [operandStack + eax*4], ebx
	add eax, 1
	mov [stackPointer], eax
  jmp main

quit:   ;free all and quit
  mov ecx, STACK_SIZE
  sub ecx,1
  .freeLoop:
    pushad   ;backup regisers
    pushfd   ;backup EFLAGS
    push dword [operandStack + 4*ecx]
    call free
    loop .freeLoop
  mov dword eax, SYS_EXIT
  mov dword ebx, 0
  int 0x80
  ret  ;in case sys_exit didn't work

plus: ;pop two operands and push the sum of them
	checkStackUnderflow 2
	;If got here, we got at least 2 operands in the stack
	mov ecx, [stackPointer]
	mov eax, [operandStack + 4*ecx]  ;eax holds the last inserted operand
	sub ecx, 1
	mov ebx, [operandStack + 4*ecx]  ;ebx holds the before last inserted operand
	sub ecx, 1
	mov [stackPointer], ecx  ;update stackPointer (reduces it by 2)
	;TODO: continue


popAndPrint: ;pop one operand and print it's value to STDOUT
	checkStackUnderflow 1
	mov eax, [stackPointer]
	sub eax, 1  ;because stack pointer counts what it's in the stack
	mov edx, 0
	mov edx, [operandStack + eax] ;the pointer to the first node
	mov byte dl, [edx]
	binarytoHexaChars  ;now in ecx the right byte
	mov eax, SYS_WRITE
	mov	ebx, STDOUT		;file descriptor
	mov	edx, 2	;message length
	int	0x80		;call kernel
	.finishedprint:
		mov eax, SYS_WRITE
		mov	ebx, STDOUT		;file descriptor
		mov ecx, '\n'
		mov	dword edx, 1	;message length
		int	0x80		;call kernel
		popOperand
		jmp main

duplicate:
  ;push to the stack a copy of the top operand in the stack
	checkStackUnderflow 1
	checkStackOverflow
	pushad   ;backup regisers
	pushfd   ;backup EFLAGS
	push 5
	call malloc  ;after this, eax holds the pointer to the block of memory, representing one node
	popad
	mov edx, [stackPointer]
	mov ebx, [operandStack + 4*edx]
	mov edx, [ebx]
	mov [eax], edx  ;the allocated node will be a copy of the given node
	mov edi, eax
	mov esi, 0
	mov [eax + 1], esi
	mov ecx, eax   ;ecx will hold the prev node
	cmp [ebx + 1], esi  ;check if the given node has a next node
	jne .nextNode    ;if it has a next node, let's handle it!
	ret              ;else, get the hell out of this method
	.nextNode:
		mov ebx, [ebx + 1]   ;ebx is the pointer to the next node
		pushad   ;backup regisers
		pushfd   ;backup EFLAGS
		push 5
		call malloc  ;after this, eax holds the pointer to the block of memory, representing one node
		popad
		mov [ecx + 1], eax   ;the next of the prev is this node
		mov ecx, eax         ;the prev is now this
		mov edx, [ebx]
		mov [eax], edx   ;the node it now a copy (the first 32 bits)
		mov [eax + 1], esi     ;now the next of the prev is 0
		;This section will check if we have a next node at all
		cmp [ebx + 1], esi
		jne .nextNode
	;edi holds the pointer to the first link of the duplicate number
	mov ecx, stackPointer
	sub ecx, 1
	.makeRoom:
		mov eax, [operandStack + 4*ecx]   ;eax holds the pointer to this operand
		mov [operandStack + 4*(ecx+1)], eax   ;the next operand in the stack is like it's prev
		sub ecx, 1
		cmp ecx, -1
		jne .makeRoom
	mov [operandStack], edi       ;the first operand in the stack is the new one
	ret


power:
  ;X is the top operand, Y is the second operand. Compute X*(2^Y)
  ;if Y>200, it's an error and we should print error and leave the stack as is

powerMinus:
  ;X is the top operand, Y is the second operand. Compute X*(2^(-Y))
  ;The result may not be an integer, we should keep only the integer part

numOf1Bits:
  ;pop one operand and push the number of 1 bits in the number
	checkStackUnderflow 1
	checkStackOverflow
	;If got here, we got at least 1 operand in the stack
	mov eax, 0
	mov ecx, [stackPointer]
	mov eax, [operandStack + 4*ecx]  ;eax holds the pointer to the first node of the last inserted operand
	sub ecx, 1
	mov [stackPointer], ecx  ;update stackPointer (reduces it by 1)
	mov ebx, [eax]
	mov edx, 0   ;edx will be our counter of 1s
	.loopUntill0:
		shr ebx, 28
		;now in ebx we got only the number in binary
		mov ecx, 4
		.loopThisLink:
			shr ebx, 1
			jc .addToCounter  ;if the carry is on, we shifted 1
			loop .loopThisLink
			jmp .endLoopLink
			.addToCounter:
				add edx, 1
				loop .loopThisLink
				jmp .endLoopLink
		.endLoopLink:
		mov ebx, [eax + 1]  ;ebx holds the pointer value only
		mov esi, 0
		cmp ebx, esi
		jne .loopUntill0
		;TODO: MAKE IT INSERTED TO OPERAND STACK
		;TODO: CHANGE THE WHOLE THING SO IT WILL NOT BE HASOOM BY EDX SIZE
		;WHEN EDX IS BIGGER THAN FF (hex), WE MAKE IT A NODE MAKE EDX 0. IN THE END, WE make
		;THE SHEERIT A NODE AND INSERT IT
		ret


squareRoot:
  ;pop one operand from the stack, and push the result, only the integer part

read:
  ;the number is in buffer, address 0 terminated
  ;read and every two chars convert to byte, and malloc the node (5 bytes), and than loop to make a list, until '\n'
  ;jmp main
