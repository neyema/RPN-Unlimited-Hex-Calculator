STACK_SIZE equ 5
INPUT_SIZE equ 80
ASCII equ 48

STDIN equ 0
STDOUT equ 1

SYS_READ equ 0x03
SYS_WRITE equ 0x04
SYS_EXIT equ 0x01

%macro errorPrompt 1
	pushad
	push dword %1
	call printf
	add esp, 4
	popad
  jmp quit
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

%macro free 0  ;in eax the address to the fisrt node of the operand
	%%freeLoop:
		cmp eax, 0
		je %%endfree
		mov ebx, [eax+1]   ;save the address of next
		pushad   ;backup regisers
		pushfd   ;backup EFLAGS
		push eax
		call free
		pop eax
		popfd
		popad
		mov dword eax, ebx
		jmp %%freeLoop
	%%endfree:
%endmacro

section .bss
  operandStack: resb STACK_SIZE*4  ;each element is pointer (4 bytes) to node
  buffer: resb INPUT_SIZE
	charstoprint: resb 2 ;place to store 2 bytes before printing

section .rodata
  calcPrompt: db "calc: ",0
  invalidInput: db "Error: Invalid Input!",10,0
  stackOverflow: db "Error: Operand Stack Overflow",10,0
  stackUnderflow: db "Error: Insufficient Number of Arguments on Stack",10,0
	newLine: db "",10,0

section .data
  stackPointer: dd 0  ;the index of the next empty slot in operand stack
  previousNode: dd 0  ;contains address of the node
  currentNode: dd 0  ;pointer to the node, holds the address to where the node start
	inputLastIndex: dd 0
	mallocHelper: dd 0       ;helper to all malloc functions, will hold pointers

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
	cmp ecx, INPUT_SIZE
	jl checkBufferLoop
	;we can assume the input is not empty line, so ecx >= 0
endOfInput: ;buffer is valid
  ;we start from the end, build node from 2 bytes, this is prev
  ;than create current, connect the previos node to the current
  ;in that way, the digits at the start will be in the last node
	sub ecx, 1
	mov [inputLastIndex], ecx
	;now create first node
	pushad
	push 5
	call malloc
	mov [currentNode], eax ;in eax the pointer to the memory
	add esp, 4
	popad
	hexatoBinary ;now in dl the byte
	sub ecx, 1
	mov eax, [currentNode]
	mov byte [eax], dl
	cmp ecx, 0
	jl pushOperand  ;was one digit, in dl the 4 right bytes are 0, it's cool!
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
createNextNode:
	cmp ecx, 0
	jl main
	mov eax, [currentNode]
	mov [previousNode], eax  ;prev = curr
	pushad
	push 5
	call malloc
	mov [currentNode], eax ;in eax the pointer to the memory
	add esp, 4
	popad
	hexatoBinary ;now in dl the byte
	sub ecx, 1
	mov eax, [currentNode]
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
    free
    add ecx, 1
		cmp ecx, [stackPointer]
		jl .freeLoop
  .exit:
		mov dword eax, SYS_EXIT
	  mov dword ebx, 0
	  int 0x80
	  ret  ;in case sys_exit didn't work

plus: ;pop two operands and push the sum of them
	;IDEA: sum each link into the before last operand's links (override it), and free
	;the last operand's links
	checkStackUnderflow 2
	;If got here, we got at least 2 operands in the stack
	mov ecx, [stackPointer]
	mov eax, [operandStack + 4*ecx]  ;eax holds a pointer to the last inserted operand
	sub ecx, 1
	mov ebx, [operandStack + 4*ecx]  ;ebx holds a pointer to the before last inserted operand
	mov [stackPointer], ecx  ;update stackPointer (reduces it by 1)
	mov edi, 0               ;in edi is the artifitial carry
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
		;TODO: what to do if carry is 1?
		mov edx, 0
		mov dl, [ebx]           ;move the numeric value of that link to dl
		add edx, edi            ;add the carry to the numeric value
		mov edi, edx
		shr edi, 8      	    ;so we can get the artifitial carry, edi now contains 00.....0 or 00.....1
		mov [ebx], dl         ;now the link have the value of the sum of the carry and itself
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
			mov ebx, [ebx + 1]    ;ebx now points to the next link
			jmp .whileCarry1

	.makeLinkWithCarry:
		;ebx points to the last link of it's list
		;TODO: CREATE A LINK WITH THE VALUE OF EDI (CARRY) AND CONNECT IT

	.beforeLastInertedOperand0:
		;if it gets here, lastInsertedOperand is not 0, so we will not stop immidietly
		;if it gets here, the list in eax has a next.
		;the list in ebx does not have a next
		;IDEA: will make the next of the list in ebx the list in eax, and release all the links
		;before the next of curr link in eax
		mov edx, 0
		mov ecx, 0
		mov cl, [eax]         ;moves the numeric value of this link to cl
		mov dl, [ebx]         ;moves the numeric value of this link to dl
		add edx, edi          ;add carry from prev sum to value of edx
		add edx, ecx     		  ;do the sum itself
		mov edi, edx    	    ;copy numeric value of sum
		shr edi, 8      	    ;so we can get the artifitial carry, edi now contains 00.....0 or 00.....1
		mov [ebx], dl    	    ;now the link will have the value of the sum (1 byte without the carry)

		mov eax, [eax + 1]     ;now eax holds the pointer to it's next link
		mov [ebx + 1], eax     ;now the next of the link in ebx is the list that eax holds
		;TODO: FREE UNTILL EAX in it's list (included eax)
		;handle the carry for curr link
		;TODO: MAYBE THESE LINES ARE NEEDED?
		;mov edx, 0
		;mov dl, [ebx]           ;move the numeric value of that link to dl
		;add edx, edi            ;add the carry to the numeric value
		;mov edi, edx
		;shr edi, 8      	    ;so we can get the artifitial carry, edi now contains 00.....0 or 00.....1
		;mov [ebx], dl         ;now the link have the value of the sum of the carry and itself
		mov ebx, [ebx + 1]       ;ebx now holds a pointer to it's next
		.whileCarry1Again:
			cmp edi, 0
			je .stopSum   ;tere's no more carry
			cmp dword [ebx + 1], 0   ;if it doesn't have a next
			je .makeLinkWithCarry    ;make a next link with the carry
			mov edx, 0
			mov ebx, [ebx + 1]
			mov dl, [ebx]           ;move the numeric value of that link to dl
			add edx, edi            ;add the carry to the numeric value
			mov edi, edx
			shr edi, 8      	    ;so we can get the artifitial carry, edi now contains 00.....0 or 00.....1
			mov [ebx], dl         ;now the link have the value of the sum of the carry and itself
			mov ebx, [ebx + 1]    ;ebx now points to the next link
			jmp .whileCarry1Again
	.stopSum:
		mov ecx, [stackPointer]
		add ecx, 1
		mov eax, [operandStack + 4*ecx]  ;eax holds a pointer to the operand that we need to free
		;TODO: free the memory that eax points to
		ret

;idea: using a loop, push to stack eax, which will contain the 2 relevant bytes
;than, in a loop, pop each register, and print the 2 first bytes in it
popAndPrint:  ;pop one operand and print it's value to STDOUT
	mov ebx, [stackPointer]
	mov eax, [operandStack+4*ebx]
	.push:

	;pop operand
	mov dword ebx, [stackPointer]
	sub ebx, 1  ;we want the last operand on stack
	mov eax, [operandStack+4*ebx]
	free ;for free, in eax the address to the first node of the operand
	mov [stackPointer], ebx
	jmp main

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
	;edi holds the pointer to the first link of the duplicate number
	mov dword ecx, stackPointer
	;.makeRoom:
	;	mov eax, [operandStack + 4*ecx]   ;eax holds the pointer to this operand
	;	mov [operandStack + 4*(ecx+1)], eax   ;the next operand in the stack is like it's prev
	;	sub ecx, 1
	;	cmp ecx, -1
	;	jne .makeRoom
	mov [operandStack + 4*ecx], edi       ;the first operand in the stack is the new one
	mov eax, [stackPointer]
	add eax, 1
	add [stackPointer], eax                ;we have one more operand in the stack now
	jmp main                                   ;GO HOME YOU PUNK! (now an amazing guitar solo by Dimebag is played)

power:
  ;X is the top operand, Y is the second operand. Compute X*(2^Y)
  ;if Y>200, it's an error and we should print error and leave the stack as is
	checkStackUnderflow 2

	mov eax, [stackPointer]
	sub eax, 1    ;make stackPointer to be the index of the last inserted operand
	mov ebx, [operandStack + 4*eax]   ;ebx has the pointer to X
	sub eax, 1
	mov ecx, [operandStack + 4*ecx]   ;ecx has the pointer to Y
	cmp dword [ecx + 1], 0            ;if Y is bigger than 0xFF (0xFF > 200)
	jne .error
	mov ecx, [ecx]        ;now ecx holds the Y number
	cmp ecx, 200
	jg .error          ;if it's bigger than 200, we got an error! funnnnnn
	;to recap: if we got here, ecx holds legal Y. ebx holds pointer to first link of X.
	.shftLoop:
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
		mov dword [eax], 0         ;numeric value of the new link is 0
		mov dword [eax + 1], ebx   ;next of this link is the first link in ebx's list
		mov ebx, eax               ;the new first link in ebx's list is the new link we create (eax points to it)
		sub ecx, 8
		jmp .shftLoop
		.ySmallerEq8:
			;TODO: WRITE IT
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
			mov esi, dh       ;take the carry with me!
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
				mov esi, dh       ;take the carry with me!
				cmp dword [edi + 1], 0
				je .checkForNewLink
				mov edi, [edi + 1]   ;make edi point to the next link
				jmp .loopEveryLink   ;go to the next link
	.checkForNewLink:
		;edi points to a link with no next
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
		mov [edi + 1], eax        ;the next of edi's link will be eax's link
		.endCheckForNewLink:
		sub ecx, 1                ;sub the number of shifts that left
		cmp ecx, 0                ;if we got no more shifts to do
		je .freeAndGoToMain
		jmp .shftLoop
	.freeAndGoToMain:
		;TODO: FREE Y
		;reduce stackPointer by 1 after we free Y
		mov eax, [stackPointer]
		sub eax
		mov [stackPointer], eax
		;now we will move the updated X's list (after the computation) to a new place
		;in the stack. It will replace Y in it's place
		mov ebx, [operandStack + 4*eax]   ;ebx points to X after the computation
		sub eax   ;now eax is the right offset for Y's place
		mov [operandStack + 4*eax], ebx    ;puck! no more Y. ONLY X.
		jmp main
	.error:
		;TODO: WRITE ERROR
		jmp main


powerMinus:
  ;X is the top operand, Y is the second operand. Compute X*(2^(-Y))
  ;The result may not be an integer, we should keep only the integer part

numOf1Bits:
	;TODO: free the prev linked list
  ;pop one operand and push the number of 1 bits in the number
	;The idea:
	;WHEN EDX IS BIGGER THAN FF (hex), WE MAKE IT A NODE MAKE EDX 0. IN THE END, WE MAKE
	;THE SHEERIT A NODE AND INSERT IT
	checkStackUnderflow 1
	;If got here, we got at least 1 operand in the stack
	mov eax, 0
	mov ecx, [stackPointer]
	sub ecx, 1
	mov eax, [operandStack + 4*ecx]  ;eax holds the pointer to the first node of the last inserted operand
	;sub ecx, 1
	;mov [stackPointer], ecx  ;update stackPointer (reduces it by 1)
	;mov dword [eax + 1], 2397654332          ;DEBUG ONLY!
	mov ebx, [eax]     ;ebx is the value of the first 4 bytes of the node itself
	mov edi, 0         ;edi is the pointer to the first node of the counter
	mov edx, 0         ;edx will be our counter of 1s
	.loopUntill0:
		shl ebx, 24   ;added in debug
		shr ebx, 24
		;now in ebx we got only the number in binary
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
		.deb:
		mov [mallocHelper], eax   ;pointer to malloced is in eax
		add esp, 4
		popfd
		popad
		mov eax, [mallocHelper]
		;shl edx, 24             ;the begining of edx will be the number, and the rest will be 0
		mov [eax], dl     ;value of edx is byte at most, so it's fine using dl
		mov [eax + 1], edi      ;the change the next link of this link
		mov edi, eax            ;change the curr link to this link
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
			.deb2:
			mov [mallocHelper], eax   ;pointer to malloced is in eax
			add esp, 4
			popfd
			popad
			mov eax, [mallocHelper]
			mov byte [eax], 0     ;value 0
			mov dword [eax + 1], 0     ;the next link will be 0 to
			mov edi, eax                ;make edi point to the new link
		.endOfLastLink:
			;eax holds a pointer to the first link of the count
			mov ecx, [stackPointer]
			sub ecx, 1
			;TODO: free the linked list in [operandStack + ecx*4]
			mov [operandStack + ecx*4], eax   ;insert it to the operand stack, instead of the prev number
			jmp main
		.checkAndBuildLink:
			;pre: counter is in edx
			;     pointer to the curr node is in edi
			cmp edx, 11111111b     ;value of FF in hex
			je .buildLink          ;we need to build a new link
			ret                   ;if we dont need to build a new link, ret
			.buildLink:
				pushad   ;backup regisers
				pushfd   ;backup EFLAGS
				push 5
				call malloc  ;after this, eax holds the pointer to the block of memory, representing one node
				mov [mallocHelper], eax   ;pointer to malloced is in eax
				add esp, 4
				popfd
				popad
				mov eax, [mallocHelper]
				mov byte [eax], 11111111b     ;FF in hex
				cmp edi, 0       ;if it's the first link we ever inserted
				je .firstLink
				;if we got here, it's not the first link we ever inserted
				mov [eax + 1], edi     ;change the pointer of the next link
				mov edi, eax           ;change the curr link to be the last inserted link
				jmp .endOfBuildLink
				.firstLink:
					mov dword [eax + 1], 0      ;there is no next for this link
				.endOfBuildLink:
				mov edx, 0
				ret

squareRoot:
  ;pop one operand from the stack, and push the result, only the integer part
