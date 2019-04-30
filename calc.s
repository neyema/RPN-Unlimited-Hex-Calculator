STACK_SIZE equ 5
INPUT_SIZE equ 82
ASCII equ 48

STDIN equ 0
STDOUT equ 1
STDERR equ 2

SYS_READ equ 0x03
SYS_WRITE equ 0x04
SYS_EXIT equ 0x01

%macro errorPrompt 1
	pushad
	pushfd
	push dword %1
	call printf
	add esp, 4
	popad
	popfd
  jmp myCalc
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

%macro cleanbuffer 0  ;cleans the buffer from leading '0' at the left
	mov eax, 0
	%%find:
		cmp eax, [inputLastIndex]
		je %%indent
		cmp byte [buffer+eax], '0'
		jne %%indent  ;found the first char that is not zero
		add eax, 1
		jmp %%find
	%%indent:
		mov dword edx, [inputLastIndex]
		sub dword edx, eax
		mov [inputLastIndex], edx
	  ;the last index without leading '0'
		mov ecx, 0  ;to change all chars in buffer
	%%indentloop:
		cmp ecx, [inputLastIndex]
		jg %%endcleanbuffer
		mov byte bl, [buffer+ecx+eax]  ;ebx<- buffer+ecx+eax (the char to change with)
		mov byte [buffer+ecx], bl  ;changed
		add ecx, 1
		jmp %%indentloop
		%%endcleanbuffer:
%endmacro

%macro checkStackOverflow 0
  mov dword eax, [stackPointer]
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

%macro hexatoBinary 0  ;assume in ecx the index in buffer we want to convert
	mov dl, 0
	mov dl, [buffer+ecx]
	cmp byte dl, 65
	jge %%char
	sub byte dl, ASCII
	jmp %%endhexatoBinary
	%%char:
		sub byte dl, 55
	%%endhexatoBinary:
%endmacro

%macro freeMac 0  ;in eax the address to the fisrt node of the operand
	%%freeLoop:
		cmp eax, 0
		je %%endfree
		mov ebx, [eax+1]   ;save the address of next
		pushad   ;backup regisers
		pushfd   ;backup EFLAGS
		push eax
		call free
		add esp, 4
		popfd
		popad
		mov dword eax, ebx
		jmp %%freeLoop
	%%endfree:
%endmacro

;this one only to use aftre v operation
;removes the leading zeros from the new X, which is on top of stack
;update ths operand stack, so x is pointing to the leading zero
%macro removeleading0 0
	mov ecx, [stackPointer]
	sub ecx, 1
	mov eax, [operandStack+4*ecx]
	mov ebx, eax ;ebx is prev
	cmp dword [eax+1], 0
	je %%endremoveleading0  ;next is 0, so only one node, don't do nothing
	%%endofoperand:
		cmp dword [eax+1], 0  ;the last node of this operand
		je %%check
		mov eax, [eax+1]
		cmp ebx, [operandStack+4*ecx]  ;ebx is to the first node, should not change
		je %%endofoperand
		mov ebx, [ebx+1]  ;inc the prev also
		jmp %%endofoperand
	%%check:
		cmp byte [eax], 0
		jne %%endremoveleading0
		mov dword edx, [eax+1]
		cmp edx, 0
		mov dword [ebx+1], edx ;prev.next = curr.next
		freeMac ;freeing the node eax, bc it's zero node, and we remove it from the operand
		mov eax, [operandStack+4*ecx]
		mov ebx, eax ;ebx is prev
		jmp %%endofoperand
	%%endremoveleading0:
%endmacro

%macro debugInput 0
	cmp byte [debugFlag], 0
	je %%enddebugFlag
	mov eax, SYS_WRITE
	mov	ebx, STDERR		;file descriptor
	mov ecx, inputDebug
	mov	edx, 10	;message length
	int	0x80		;call kernel
	mov edx, eax ;in eax the return value of sys_read, number of bytes
	mov eax, SYS_WRITE
	mov	ebx, STDERR		;file descriptor
	mov ecx, buffer
	int	0x80		;call kernel
	%%enddebugFlag:
%endmacro

%macro debugResult 0 ;result is the last operand on stack
	cmp byte [debugFlag], 0
	je %%notdebug
	mov eax, SYS_WRITE
	mov	ebx, STDERR		;file descriptor
	mov ecx, resultDebug
	mov	edx, 11	;message length
	int	0x80		;call kernel
	;TODO: print the top operand in stack
	mov ebx, [stackPointer]
	sub ebx, 1  ;last operand on stack
	mov eax, [operandStack+4*ebx]
	push dword 0  ;mark to the end of the nodes
%%pushop:
	cmp eax, 0
	je %%convert
	push eax
	mov dword eax, [eax+1]  ;eax<-next
	jmp %%pushop
%%convert:
	pop eax  ;pop address to node
	cmp eax, 0
	je %%enddebugFlag  ;the mark to stop
	mov byte dl, [eax] ;in dl, 2 digits, each one 4 bits
	shr dl, 4   ;4 bits at left
	cmp byte dl, 9
	jle %%.number
	add byte dl, 55
	jmp %%.second
	%%.number:
		add byte dl, ASCII
	%%.second:
		mov byte [charstoprint], dl
		mov byte dl, [eax] ;now convert the second digit
		shl dl, 4  ;4 bits at the right
		shr dl, 4
		cmp byte dl, 9
		jle %%.secondisnumber
		add byte dl, 55
		jmp %%print
	%%.secondisnumber:
		add byte dl, ASCII
%%print:
	mov byte [charstoprint+1], dl
	mov eax, SYS_WRITE
	mov ebx, STDOUT
	mov ecx, charstoprint
	mov edx, 2
	int 0x80
	jmp %%convert
%%enddebugFlag:
	mov eax, SYS_WRITE
	mov	ebx, STDOUT		;file descriptor
	mov ecx, newLine
	mov	dword edx, 1	;message length
	int	0x80		;call kernel
%%notdebug:
%endmacro

section .bss
  operandStack: resb (STACK_SIZE+1)*4  ;each element is pointer (4 bytes) to node
	;it's +1 because in numbOf1Bits we will want to use plus method
  buffer: resb INPUT_SIZE
	charstoprint: resb 2 ;to store 2 bytes before printing

section .rodata
  calcPrompt: db "calc: ",0
  invalidInput: db "Error: Invalid Input!",10,0
	wrongYvalue: db "wrong Y value",10,0  ;print when Y>200
  stackOverflow: db "Error: Operand Stack Overflow",10,0
  stackUnderflow: db "Error: Insufficient Number of Arguments on Stack",10,0
	yBigger200Msg: db "wrong Y value", 10, 0   ;TODO: CHANGE IT TO AS THEY WANT
	newLine: db "",10,0
	inputDebug: db "input is: ",0
	resultDebug: db "result is: ",0

section .data
  stackPointer: dd 0  ;index of the next empty slot in operand stack
  previousNode: dd 0  ;contains address of the node
  currentNode: dd 0  ;pointer to the node, holds the address to where the node start
	inputLastIndex: dd 0
	mallocHelper: dd 0       ;helper to all malloc functions, will hold pointers
	initStackPointer: dd 0   ;helper for numOf1Bits, will save the stackPointer when we just started this method
	replacedList: dd 0       ;helper for numOf1Bits, will save the pointer to the list that we are replacing in the stack
	freeUntillNotIncluded: dd 0   ;helper for plus, we will free untill this pointer (not included)
	Y: dd 0 ;pointer to Y of v operation (X*2^(-Y))
	debugFlag: db 0 ;1 iff debug mode is on
	opCounter: dd 0  ;counts all operations, return value of myCalc
	formatint: db "%d", 10, 0
	isExsit: dd 0
	startOfFree: dd 0

section .text
align 16
 global main
 global myCalc
 extern printf  ;use when there is '\n' at the end
 extern fflush
 extern malloc
 extern calloc
 extern free
 ;extern gets
 ;extern fgets ;im using system call SYS_READ

main:
	push ebp
	mov ebp, esp
	pushad

	mov eax, [ebp+8] ;argc
	cmp eax, 2
	jl startcalc ;there is only one argument, so debug flag is off
	mov esi, [ebp + 12] ;argv
	mov eax, [esi + 4] ;2nd argument
	cmp word [eax], "-d" ;word is 16 bits, 2 chars
	jne startcalc
	mov byte [debugFlag], 1
	startcalc:
		mov byte [opCounter], 0
		mov dword [opCounter], 0
		call myCalc
	;TODO: print myCalc return value
	push eax
	push formatint
	call printf
	add esp, 4  ;format is db
	pop eax

	popad
	mov esp, ebp
	pop ebp
	ret

myCalc:
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
	add dword [opCounter], 1 ;operation counter
  cmp byte [buffer], '+'
  je plusAtmosphere
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
	sub dword [opCounter], 1
	debugInput
	checkStackOverflow
  mov ecx, 0  ;stores input length
checkBufferLoop:
	mov bl, 0
  mov bl, [buffer+ecx]
  cmp byte bl, 10   ;10 is ascii of '\n'
  je endOfInput
  checkBuffer ecx
  add ecx, 1
	cmp ecx, INPUT_SIZE
	jl checkBufferLoop
	;we can assume the input is not empty line, so ecx >= 0
endOfInput: ;buffer is valid
  ;we start from the end, build node from 2 bytes, this is prev
  ;than create current, connect the previos node to the current
  ;in that way, the digits at the start will be in the last node
	sub ecx, 1
	mov [inputLastIndex], ecx
	cleanbuffer
	mov ecx, [inputLastIndex]
	;now create first node
createFirstNode:
	pushad
	push 5
	call malloc
	mov [currentNode], eax ;in eax the pointer to the memory
	mov byte [eax], 0
	mov dword [eax + 1], 0
	add esp, 4
	popad
	hexatoBinary ;in ecx, the index we want to convert, and after this, in dl the converted byte
	sub ecx, 1 ;one char converted
	mov eax, [currentNode]
	mov byte [eax], dl
	cmp ecx, 0
	jl pushOperand  ;was one digit, in dl the 4 right bits are 0, it's cool!
	mov byte bl, dl
	hexatoBinary
	sub ecx, 1
	shl dl, 4
	or bl, dl
	mov byte [eax], bl
pushOperand: ;the next of previos node is 0 now (will change)
	mov dword ebx, [stackPointer]
	mov dword [operandStack + 4*ebx], eax
	add dword ebx, 1
	mov [stackPointer], ebx
	mov dword [eax+1], 0  ;it is 0 just for now (in case there are no more nodes)
createNextNode:
	cmp ecx, 0
	jl myCalc
	mov eax, [currentNode]
	mov [previousNode], eax  ;prev = curr
	pushad
	push 5
	call malloc
	mov [currentNode], eax ;in eax the pointer to the memory
	mov dword [eax + 1], 0
	mov byte [eax], 0
	add esp, 4
	popad
	hexatoBinary ;now in dl the byte
	sub ecx, 1
	mov eax, [currentNode]
	mov dword [eax + 1], 0
	mov byte [eax], dl  ;moving to the node for the 'A' case, where need to insert '0A'
	cmp ecx, 0
	jl .connect  ;was one digit, in dl the 4 right bytes are 0, it's cool! we finished reading
	mov byte bl, dl
	hexatoBinary
	sub ecx, 1
	shl dl, 4
	or bl, dl
	mov byte [eax], bl
.connect:
	mov edi, [currentNode]    ;edi holds the pointer to the current node
	mov esi, [previousNode]   ;esi holds the pointer to the prev node
	mov [esi + 1], edi        ;set the next of the prev node to the curr node
	jmp createNextNode        ;go and create more nodes like this beautiful snowflake

quit: ;free all and quit
  mov dword ecx, 0
	cmp ecx, [stackPointer]
	je .exit  ;stackPointer =0 means stack is empty
  .freeLoop:
    mov dword eax, [operandStack + 4*ecx]
    freeMac
    add ecx, 1
		cmp ecx, [stackPointer]
		jl .freeLoop
  .exit:
		mov dword eax, [opCounter] ;return value
	  ret ;ret to main

plusAtmosphere:
	;So main can use plus without call it. Main will jump here
	call plus
	debugResult ;the last operand in stack
	jmp myCalc

plus: ;pop two operands and push the sum of them
	;IDEA: sum each link into the before last operand's links (override it), and free
	;the last operand's links
	checkStackUnderflow 2
	;If got here, we got at least 2 operands in the stack
	mov dword [freeUntillNotIncluded], 0   ;make it 0 so we can reuse
	mov ecx, [stackPointer]
	sub ecx, 1
	mov eax, [operandStack + 4*ecx]  ;eax holds a pointer to the last inserted operand
	mov [startOfFree], eax
	sub ecx, 1
	mov ebx, [operandStack + 4*ecx]  ;ebx holds a pointer to the before last inserted operand
	;add ecx, 1
	;mov [stackPointer], ecx  ;update stackPointer (reduces it by 1)
	mov edi, 0               ;in edi is the artifitial carry
	mov cl, [eax]         ;moves the numeric value of this link to cl
	mov dl, [ebx]         ;moves the numeric value of this link to dl
	add edx, ecx     		  ;do the sum itself
	mov edi, edx    	    ;copy numeric value of sum
	shr edi, 8      	    ;so we can get the artifitial carry, edi now contains 00.....0 or 00.....1
	mov [ebx], dl    	    ;now the link will have the value of the sum (1 byte without the carry)
	.sumLink:
		cmp dword [eax + 1], 0      ;if the next one is empty
		je .lastInsertedOperand0
		cmp dword [ebx + 1], 0      ;if the next one is empty
		je .beforeLastInertedOperand0
		;if we got here, both operands have the next link, and curr link was already computed
		mov ecx, 0
		mov edx, 0
		mov eax, [eax + 1]    ;eax will hold a pointer to the next link in this list
		mov ebx, [ebx + 1]    ;ebx will hold a pointer to the next link in this list
		mov cl, [eax]         ;moves the numeric value of this link to cl
		mov dl, [ebx]         ;moves the numeric value of this link to dl
		add edx, edi          ;add carry from prev sum to value of edx
		add edx, ecx     		  ;do the sum itself
		mov edi, edx    	    ;copy numeric value of sum
		shr edi, 8      	    ;so we can get the artifitial carry, edi now contains 00.....0 or 00.....1
		mov [ebx], dl    	    ;now the link will have the value of the sum (1 byte without the carry)
		jmp .sumLink

	.lastInsertedOperand0:
		;if it gets here, the list in ebx maybe has a next, the list in eax doesn't
		cmp edi, 0
		je .stopSum   ;we have no point in continue summing anymore, because carry is 0
		.whileCarry1:
			cmp edi, 0
			je .stopSum   ;there's no more carry
			;handle the carry for curr link
			cmp dword [ebx + 1], 0   ;if it doesn't have a next
			je .makeLinkWithCarry    ;make a next link with the carry
			mov edx, 0
			mov ebx, [ebx + 1]      ;it sure does have a next
			mov dl, [ebx]           ;move the numeric value of that link to dl
			add edx, edi            ;add the carry to the numeric value
			mov edi, edx
			shr edi, 8      	    ;so we can get the artifitial carry, edi now contains 00.....0 or 00.....1
			mov [ebx], dl         ;now the link have the value of the sum of the carry and itself
			jmp .whileCarry1

	.makeLinkWithCarry:
		;ebx points to the last link of it's list
		pushad   ;backup regisers
		pushfd   ;backup EFLAGS
		push 5
		call malloc  ;after this, eax holds the pointer to the block of memory, representing one node
		mov [mallocHelper], eax   ;pointer to malloced memory is in eax
		add esp, 4
		popfd
		popad
		push eax             ;backup eax
		mov esi, [mallocHelper]
		mov eax, edi         ;carry now in eax
		mov [esi], al        ;carry is placed
		mov dword [esi + 1], 0       ;it will be the final link
		mov [ebx + 1], esi        ;the next of ebx's link is esi
		mov ebx, esi              ;the end of the list is esi now
		pop eax
		jmp .stopSum

	.beforeLastInertedOperand0:
		;if it gets here, lastInsertedOperand is not 0, so we will not stop immidietly
		;if it gets here, the list in eax has a next.
		;the list in ebx does not have a next
		;IDEA: will make the next of the list in ebx the list in eax, and release all the links
		;before the next of curr link in eax
		mov eax, [eax + 1]      ;get eax's next
		mov [freeUntillNotIncluded], eax  ;we need to free eax's link untill that link
		mov [ebx + 1], eax     ;now the next of the link in ebx is the list that eax holds
		.whileCarry1Again:
			cmp edi, 0
			je .stopSum   ;there's no more carry
			cmp dword [ebx + 1], 0   ;if it doesn't have a next
			je .makeLinkWithCarry    ;make a next link with the carry
			mov edx, 0
			mov ebx, [ebx + 1]      ;it sure does have a next
			mov dl, [ebx]           ;move the numeric value of that link to dl
			add edx, edi            ;add the carry to the numeric value
			mov edi, edx
			shr edi, 8      	    ;so we can get the artifitial carry, edi now contains 00.....0 or 00.....1
			mov [ebx], dl         ;now the link have the value of the sum of the carry and itself
			jmp .whileCarry1Again
	.stopSum:
		;TODO: free the memory that eax points to
		;jmp endOfEnd
		;mov ebx, [stackPointer]
		;sub ebx, 1
		;mov eax, [operandStack + 4*ebx]  ;eax points to the first link of the list that we want to free
		mov eax, [startOfFree]
		;if we got here, we need to free untill we hit this link
		freeLoopPlus:
			cmp eax, dword [freeUntillNotIncluded]  ;will work if freeUntill... is 0 (untouched) as well
			je endOfEnd
			mov ebx, [eax+1]   ;save the address of next
			pushad   ;backup regisers
			pushfd   ;backup EFLAGS
			push eax
			call free
			afterFree:
			add esp, 4
			popfd
			popad
			mov dword eax, ebx
			jmp freeLoopPlus
	endOfEnd:
		sub dword [stackPointer], 1
		ret

;idea: using a loop, push to stack eax, which will contain the 2 relevant bytes
;than, in a loop, pop each register, and print the 2 first bytes in it
popAndPrint:  ;pop one operand and print it's value to STDOUT
	checkStackUnderflow 1
	mov ebx, [stackPointer]
	sub ebx, 1
	mov [stackPointer], ebx ;pop operand
	mov eax, [operandStack+4*ebx]
	push dword 0  ;mark to the end of the nodes
firstnode:
	mov byte dl, [eax] ;in dl, 2 digits, each one 4 bits
	shr dl, 4   ;4 bits at left
	cmp byte dl, 9
	jle .number
	add byte dl, 55
	jmp .second
	.number:
		add byte dl, ASCII
	.second:
		mov byte [charstoprint], dl
		cmp byte dl, 48 ;48 is '0'
		jne push  ;regular!!!
		mov byte dl, [eax] ;now convert the second digit
		shl dl, 4  ;4 bits at the right
		shr dl, 4
		cmp byte dl, 9
		jle .secondisnumber
		add byte dl, 55
		jmp .print
	.secondisnumber:
		add byte dl, ASCII
	.print: ;the first char is zero, so print just the second
		mov byte [charstoprint+1], dl
		mov eax, SYS_WRITE
		mov ebx, STDOUT
		mov ecx, charstoprint+1
		mov dword edx, 1
		int 0x80
	mov ebx, [stackPointer]
	mov eax, [operandStack+4*ebx]
	mov dword eax, [eax+1]
push:
	cmp dword eax, 0
	je convert
	push eax
	mov dword eax, [eax+1]  ;eax<-next
	jmp push
convert:
	pop eax  ;pop address to node
	cmp dword eax, 0
	je end  ;the mark to stop
	mov byte dl, [eax] ;in dl, 2 digits, each one 4 bits
	shr dl, 4   ;4 bits at left
	cmp byte dl, 9
	jle .number
	add byte dl, 55
	jmp .second
	.number:
		add byte dl, ASCII
	.second:
		mov byte [charstoprint], dl
		mov byte dl, [eax] ;now convert the second digit
		shl dl, 4  ;4 bits at the right
		shr dl, 4
		cmp byte dl, 9
		jle .secondisnumber
		add byte dl, 55
		jmp print
	.secondisnumber:
		add byte dl, ASCII
print:
	mov byte [charstoprint+1], dl
	mov eax, SYS_WRITE
	mov ebx, STDOUT
	mov ecx, charstoprint
	mov edx, 2
	int 0x80
	jmp convert
end:
	mov eax, SYS_WRITE
	mov	ebx, STDOUT		;file descriptor
	mov ecx, newLine
	mov	dword edx, 1	;message length
	int	0x80		;call kernel
	;free operand
	mov dword ebx, [stackPointer]
	mov eax, [operandStack+4*ebx]
	freeMac ;for free, in eax the address to the first node of the operand
	jmp myCalc

duplicate:
  ;push to the stack a copy of the top operand in the stack
	checkStackUnderflow 1
	checkStackOverflow
	pushad   ;backup regisers
	pushfd   ;backup EFLAGS
	push 5
	call malloc  ;after this, eax holds the pointer to the block of memory, representing one node
	mov [mallocHelper], eax   ;pointer to malloced is in eax
	add esp, 4
	popfd
	popad
	mov eax, [mallocHelper]
	mov edx, [stackPointer]
	sub edx, 1
	mov ebx, [operandStack + 4*edx]
	mov edx, [ebx]
	mov [eax], edx  ;the allocated node will be a copy of the given node
	mov esi, 0
	mov [eax + 1], esi
	mov ecx, eax   ;ecx will hold the prev node
	cmp [ebx + 1], esi  ;check if the given node has a next node
	mov edx, [stackPointer]
	mov [operandStack + 4*edx], eax    ;insert it to the operand stack
	jne .nextNode    ;if it has a next node, let's handle it!
	add dword [stackPointer], 1
	jmp .end              ;else, get the hell out of this method
	.nextNode:
		mov ebx, [ebx + 1]   ;ebx is the pointer to the next node
		pushad   ;backup regisers
		pushfd   ;backup EFLAGS
		push 5
		call malloc  ;after this, eax holds the pointer to the block of memory, representing one node
		mov [mallocHelper], eax   ;pointer to malloced is in eax
		add esp, 4
		popfd
		popad
		mov eax, [mallocHelper]
		mov [ecx + 1], eax   ;the next of the prev is this node
		mov ecx, eax         ;the prev is now this
		mov edx, [ebx]
		mov [eax], edx   ;the node it now a copy (the first 32 bits)
		mov [eax + 1], esi     ;now the next of the prev is 0
		;This section will check if we have a next node at all
		cmp [ebx + 1], esi
		jne .nextNode
	add dword [stackPointer], 1      ;update the number of operands
	.end:
	debugResult
	jmp myCalc        ;GO HOME YOU PUNK! (now an amazing guitar solo by Dimebag is played)

power:
  ;X is the top operand, Y is the second operand. Compute X*(2^Y)
  ;if Y>200, it's an error and we should print error and leave the stack as is
	checkStackUnderflow 2
	mov eax, [stackPointer]
	sub eax, 1    ;make stackPointer to be the index of the last inserted operand
	mov ebx, [operandStack + 4*eax]   ;ebx has the pointer to X
	sub eax, 1
	mov ecx, [operandStack + 4*eax]   ;ecx has the pointer to Y
	cmp dword [ecx + 1], 0            ;if Y is bigger than 0xFF (0xFF > 200)
	jne .error
	mov ecx, [ecx]        ;now ecx holds the Y number
	cmp ecx, 200
	jg .error          ;if it's bigger than 200, we got an error! funnnnnn
	;to recap: if we got here, ecx holds legal Y. ebx holds pointer to first link of X.
	.shftLoop:
		mov eax, [stackPointer]
		sub eax, 1    ;make stackPointer to be the index of the last inserted operand
		mov ebx, [operandStack + 4*eax]   ;ebx has the pointer to X
		cmp ecx, 8
		jle .ySmallerEq8
		;Y>8 here
		;IDEA: create a new link, insert it to X from left, and remove 8 from ecx
		;allocate a new link:
		pushad   ;backup regisers
		pushfd   ;backup EFLAGS
		push 5
		call malloc  ;after this, eax holds the pointer to the block of memory, representing one node
		mov [mallocHelper], eax   ;pointer to malloced memory is in eax
		add esp, 4
		popfd
		popad
		mov eax, [mallocHelper]
		mov byte [eax], 0         ;numeric value of the new link is 0
		mov dword [eax + 1], ebx   ;next of this link is the first link in ebx's list
		mov ebx, eax               ;the new first link in ebx's list is the new link we create (eax points to it)
		mov eax, [stackPointer]
		sub eax, 1    ;make stackPointer to be the index of the last inserted operand
		mov [operandStack + 4*eax], ebx   ;change the head
		sub ecx, 8
		jmp .shftLoop
		.ySmallerEq8:
			;Y<= 8 here
			;IDEA: shift left 1 every link, and pass carry to the next link
			mov edi, ebx   ;edi holds a pointer to X first link
			mov esi, 0     ;esi will be our artifitial carry
			mov edx, [edi]
			shl edx, 24
			shr edx, 24
			;now edx have only the numeric value of this link
			shl edx, 1        ;shift it to do the power!
			mov [edi], dl     ;change the value of this link
			mov esi, edx
			shr esi, 8        ;take the carry with me!
			mov edx, edi
			cmp dword [edx + 1], 0
			je .checkForNewLink
			.loopEveryLink:
				;when we get here, edi points to a link that has been shifted
				;it's next hasn't been shifted yet
				mov edx, [edi + 1]
				mov edx, [edx]
				shl edx, 24
				shr edx, 24
				;now edx have only the numeric value of this link
				shl edx, 1        ;shift it to do the power!
				add edx, esi      ;add the carry
				mov eax, [edi + 1]
				mov [eax], dl     ;change the value of this link
				mov esi, edx
				shr esi, 8        ;take the carry with me!
				mov edx, [edi + 1]
				cmp dword [edx + 1], 0
				je .checkForNewLink
				mov edi, [edi + 1]   ;make edi point to the next link
				jmp .loopEveryLink   ;go to the next link
	.checkForNewLink:
		;edx points to a link with no next
		;esi holds the carry after we handled edi's shift
		cmp esi, 0
		je .endCheckForNewLink   ;we do no need to action
		;if we got here, we have overflow. sucks.
		;we will create a new link
		pushad   ;backup regisers
		pushfd   ;backup EFLAGS
		push 5
		call malloc  ;after this, eax holds the pointer to the block of memory, representing one node
		mov [mallocHelper], eax   ;pointer to malloced memory is in eax
		add esp, 4
		popfd
		popad
		mov eax, [mallocHelper]
		mov byte [eax], 1   ;it's numeric value will be 1
		mov dword [eax + 1], 0   ;it's next will be 0
		mov [edx + 1], eax        ;the next of edx's link will be eax's link
		.endCheckForNewLink:
		sub ecx, 1                ;sub the number of shifts that left
		cmp ecx, 0                ;if we got no more shifts to do
		je .freeAndGoToMain
		jmp .shftLoop
	.freeAndGoToMain:
		;TODO: FREE Y
		mov ebx, [stackPointer]
		sub ebx, 2   ;Y is the before last
		mov eax, [operandStack + 4*ebx]  ;eax is the pointer to Y's first link
		freeMac    ;free Y using free macro
		;reduce stackPointer by 1 after we free Y
		mov eax, [stackPointer]
		sub eax, 1
		mov [stackPointer], eax
		;now we will move the updated X's list (after the computation) to a new place
		;in the stack. It will replace Y in it's place
		mov ebx, [operandStack + 4*eax]   ;ebx points to X after the computation
		sub eax, 1   ;now eax is the right offset for Y's place
		mov [operandStack + 4*eax], ebx    ;puck! no more Y. ONLY X.
		debugResult
		jmp myCalc
	.error:
		errorPrompt wrongYvalue
		jmp myCalc

powerMinus:
  ;X is the top operand, Y is the second operand. Compute X*(2^(-Y))
  ;The result may not be an integer, we should keep only the integer part
	;the relevant case is Y<=200, so Y is one node
	checkStackUnderflow 2
	mov ecx, [stackPointer]
	sub ecx, 2 ;X is the top of the stack, we want Y
	mov ebx, [operandStack+4*ecx]  ;in ebx the address to the first node of Y
	;check Y>200
	cmp dword [ebx+1], 0
	jne .error ;there is next, so Y>255>200 (1 byte is maximum 255)
	mov edx, 0
	mov dl, [ebx]
	cmp edx, 200  ;equal, so there is one node
	jg .error ;Y>200
	mov [Y], ebx ;Y holds pointer to the first node
	mov byte dl, [ebx]  ;in dl the value of Y
	;idea: push to stack all nodes of X, than pop each one, shr, set carry and continue
	;eax<-X
	jmp .Yloop
	.error:
		errorPrompt wrongYvalue
	.Yloop:  ;Y iterations, using dl as counter, dh as carry
		cmp byte dl, 0
		je .end
		push dword 0
		mov ecx, [stackPointer]
		sub ecx, 1
		mov dword eax, [operandStack+4*ecx] ;the first node of the X, to start shifting
		mov byte dh, 0  ;the curry is 0, every shift
		.pushloop:
			cmp eax, 0
			je .divideby2
			push eax
			mov dword eax, [eax+1] ;maybe not needed dword
			jmp .pushloop
		;all nodes are in stack, left to right order (of the actual number)
	.divideby2:
		pop eax
		cmp dword eax, 0
		je .Yloopcondition
		shr byte [eax], 1
		jc .setcarry
		or byte [eax], dh  ;so the carry will be in the most left bit
		mov byte dh, 0
		jmp .divideby2
	.setcarry:
		or byte [eax], dh
		mov byte dh, 128  ;so dh is 10000000, it's ok bc carry is at the left when shifting right
		jmp .divideby2
	.Yloopcondition:
	  sub byte dl, 1  ;sub edx, 1
		jmp .Yloop
	.end:
		removeleading0
		mov ecx, [stackPointer]
		sub ecx, 2
		mov ebx, [operandStack+4*ecx+4] ;in ebx the pointer to X
		mov [operandStack+4*ecx], ebx ;replaced Y with X  in the stack (X will hold the result)
		mov dword eax, [Y]
		freeMac
		add ecx, 1 ;now ecx is the old index of X in the stack
		mov [stackPointer], ecx ;ecx = old stackPointer -1, pop Y and move X one slot down in the stack
		debugResult
		jmp myCalc

;TODO: add a debugResultsomewhere here after pushing the operand to stack
numOf1Bits:
  ;pop one operand and push the number of 1 bits in the number
	;The idea:
	;WHEN EDX IS BIGGER THAN FF (hex), WE MAKE IT A NODE MAKE EDX 0. IN THE END, WE MAKE
	;AND ADD IT TO THE COUNTER LST
	;THE SHEERIT IS A NODE AND PLUS IT TO THE COUNTER LST
	checkStackUnderflow 1
	;If got here, we got at least 1 operand in the stack
	mov eax, 0
	mov ebx, 0
	mov ecx, 0
	mov edx, 0
	mov edi, 0
	mov esi, 0
	mov dword [replacedList], 0
	mov dword [initStackPointer], 0
	mov ecx, [stackPointer]
	mov [initStackPointer], ecx
	sub ecx, 1
	mov eax, [operandStack + 4*ecx]  ;eax holds the pointer to the first node of the last inserted operand
	mov [replacedList], eax          ;save the head of the replaced list
	mov edi, 0         ;edi is the pointer to the first node of the counter
	mov edx, 0         ;edx will be our counter of 1s
	.loopUntill0:
		mov ebx, [eax]   ;added in debug ;ebx is the value of the first 4 bytes of the node itself
		shl ebx, 24
		shr ebx, 24
		;now in ebx we got only the number in binary of the link
		mov ecx, 8
		.loopThisLink:
			shr ebx, 1
			jc .addToCounter  ;if the carry is on, we shifted 1
			loop .loopThisLink
			jmp .endLoopLink
			.addToCounter:
				add edx, 1
				call .checkAndBuildLink
				loop .loopThisLink
				jmp .endLoopLink
		.endLoopLink:
		mov ebx, [eax + 1]  ;ebx holds the pointer value only
		mov eax, [eax + 1]  ;make it point to it's next ADDED IN DEB
		mov esi, 0
		cmp ebx, esi
		jne .loopUntill0
		cmp edx, 0
		je .checkNeed0     ;The counter is 0. We need to check if we need to insert a node or not
		;if we got here, the counter is not 0 and we need to create a link
		pushad   ;backup regisers
		pushfd   ;backup EFLAGS
		push 5
		call malloc  ;after this, eax holds the pointer to the block of memory, representing one node
		mov [mallocHelper], eax   ;pointer to malloced is in eax
		add esp, 4
		popfd
		popad
		mov eax, [mallocHelper]
		mov [eax], dl     ;value of edx is byte at most, so it's fine using dl
		mov dword [eax + 1], 0   ;it has no next
		cmp edi, 0
		je .finalFirstNode
		mov ebx, [initStackPointer]
		;We will add the new link to the operand stack as dummy, so plus
		;will detect it and do shit with it and with the counter's list
		mov [operandStack + 4*ebx], eax     ;update it in the operand stack
		add ebx, 1
		mov [stackPointer], ebx    ;make sure stack pointer is in the desired size
		pushad   ;backup regisers
		pushfd   ;backup EFLAGS
		call plus   ;make the plus
		popfd
		popad
		jmp .checkNeed0
		;now we have the prev counter + this counter in the operand stack
	.finalFirstNode:
		mov edi, eax                ;change the head of the counter
		mov esi, [initStackPointer]
		sub esi, 1
		mov [operandStack + 4*esi], eax     ;update it in the operand stack
		.checkNeed0:
			;We will create a node if it will be the only node, and it value will be 0
			cmp edi, 0
			je .build0Link       ;if no other link inserted before, create a 0 link
			jmp .endOfLastLink
		.build0Link:
			pushad   ;backup regisers
			pushfd   ;backup EFLAGS
			push 5
			call malloc  ;after this, eax holds the pointer to the block of memory, representing one node
			mov [mallocHelper], eax   ;pointer to malloced is in eax
			add esp, 4
			popfd
			popad
			mov eax, [mallocHelper]
			mov byte [eax], 0     ;value 0
			mov dword [eax + 1], 0     ;the next link will be 0 to
			mov edi, eax                ;make edi point to the new link
			mov esi, [stackPointer]
			sub esi, 1
			mov [operandStack + 4*esi], edi     ;update it in the operand stack
			add dword [stackPointer], 1         ;update the stackPointer
		.endOfLastLink:
			;eax holds a pointer to the first link of the count
			;mov ecx, [stackPointer]
			;sub ecx, 1
			mov eax, [replacedList]
			freeMac       ;free the list in eax using macro
			mov esi, [initStackPointer]
			mov [stackPointer], esi
			debugResult
			jmp myCalc
		.checkAndBuildLink:
			;pre: counter is in edx
			;     pointer to firstCounterNode is in [operandStack + 4*(stackPointer-1)] edi
			cmp edx, 11111111b     ;value of FF in hex
			je .buildLink          ;we need to build a new link
			ret                   ;if we dont need to build a new link, ret
			.buildLink:
				pushad   ;backup regisers
				pushfd   ;backup EFLAGS
				push 5
				call malloc  ;after this, eax holds the pointer to the block of memory, representing one node
				.deb:
				mov [mallocHelper], eax   ;pointer to malloced is in eax
				add esp, 4
				popfd
				popad
				mov esi, [mallocHelper]
				mov byte [esi], 11111111b     ;FF in hex
				cmp edi, 0       ;if it's the first link we ever inserted
				je .firstLink
				;if we got here, it's not the first link we ever inserted
				mov ebx, [initStackPointer]
				;We will add the new link to the operand stack as dummy, so plus
				;will detect it and do shit with it and with the counter's list
				mov [operandStack + 4*ebx], esi     ;update it in the operand stack
				add ebx, 1
				mov [stackPointer], ebx    ;make sure stack pointer is in the desired size
				mov dword [esi + 1], 0  ;it's the first link, it has no next
				;mov edi, esi           ;change this link to be the head of the counter's list
				pushad   ;backup regisers
				pushfd   ;backup EFLAGS
				call plus   ;make the plus
				popfd
				popad
				;now we have the prev counter + this counter in the operand stack
				jmp .endOfBuildLink
				.firstLink:
					mov dword [esi + 1], 0      ;there is no next for this link
					mov edi, esi                ;change the head of the counter
					mov esi, [initStackPointer]
					sub esi, 1
					mov [operandStack + 4*esi], edi     ;update it in the operand stack
				.endOfBuildLink:
				mov edx, 0
				;debugResult
				ret

squareRoot:
  ;pop one operand from the stack, and push the result, only the integer part
