; running:
; sh-4.3$ nasm -f elf *.asm; ld -m elf_i386 -s -o demo *.o                                                                                                       
; sh-4.3$ demo                                                                                                                                                   
; 1 2 fizz 4 buzz fizz 7 8 fizz buzz 11 fizz 13 14 fizzbuzz      

section .text
    global _start
    
%define CELLS 4
%define link 0
%define MODE_COMPILE 1
%define MODE_INTERPRET 0
%define IMMEDIATE -1
%define TRUE -1
%define FALSE 0

%macro NEXT 0               ; inner interpreter for indirect threaded code
    lodsd 
    jmp [eax]
%endmacro    

%macro header 4             ; magic macro for defining words and primitives
    %%link dd link
    %define link %%link
    %strlen %%name_len %1
    dd %%name_len
    db %1
    dd %3
    xt_ %+ %2 dd %4         ; execution token of body
%endmacro

%macro defprimitive 3
    header %1,%2,%3,$+4
%endmacro

%macro defword 3
    header %1,%2,%3,ENTERCOL
%endmacro

_start:
    cld
    mov ebp, RSTACK
    mov esi, REPL
    NEXT
    
defprimitive 'dup',dup,1
    mov eax, [esp]
    push eax
    NEXT
    
defprimitive 'over',over,1
    mov eax, [esp + CELLS]
    push eax
    NEXT

defprimitive 'drop',drop,1
    pop eax
    NEXT

defprimitive 'swap',swap,1
    pop eax
    pop ebx
    push eax
    push ebx
    NEXT

defprimitive 'rot',rot,1  ; ( a b c -- b c a )
    pop ecx
    pop ebx
    pop eax
    push ebx
    push ecx
    push eax
    NEXT
    
defword 'nip',nip,1
    dd xt_swap
    dd xt_drop
    dd EXITCOL
    
defword '2dup',2dup,1
    dd xt_over
    dd xt_over
    dd EXITCOL    
    
defprimitive '+',plus,1
    pop eax
    add [esp], eax
    NEXT    
    
defprimitive '-',minus,1
    pop eax
    sub [esp], eax
    NEXT        
    
defprimitive '*',multiply,1
    pop eax
    pop ebx
    mul ebx
    push eax
    NEXT

defprimitive '/',divide,1
    pop ebx
    pop eax
    xor edx, edx
    div ebx
    push eax
    NEXT
    
defprimitive '%',modulo,1
    pop ebx
    pop eax
    xor edx, edx
    div ebx
    push edx
    NEXT

defprimitive 'emit',emit,1
    mov edx, 1      ; length
    pop dword [var0]
    mov ecx, var0
    mov ebx, 1      ; stdout
    mov eax, 4      ; sys_write
    int 0x80
    NEXT
    
defprimitive 'abort',abort,1
    mov eax, 1
    int 0x80
    
defprimitive '@',fetch,1
    pop eax
    push dword [eax]
    NEXT
    
defprimitive '!',store,1
    pop edi
    pop eax
    stosd
    NEXT
    
defprimitive 'cells',cells,1
    mov eax, CELLS
    push eax
    NEXT    
        
defprimitive 'lit',lit,1        ; literal
    lodsd
    push eax
    NEXT
    
defprimitive '=',eq,1
    xor eax, eax
    pop ebx
    pop edx
    cmp ebx, edx
    jnz not_equal
    mov eax, TRUE
not_equal:
    push eax
    NEXT
    
defprimitive '<',lt,1
    xor eax, eax
    pop ebx
    pop edx
    cmp edx, ebx
    jnl not_less
    mov eax, TRUE
not_less:
    push eax
    NEXT
            
defprimitive 'state',state,1
    push state
    NEXT

defprimitive 'branch1',branch1,1
    lodsd
    pop ebx
    cmp ebx, TRUE
    jnz nobranch1
    add esi, eax
nobranch1:
    NEXT

defprimitive 'branch0',branch0,1
    lodsd
    pop ebx
    test ebx, ebx
    jnz nobranch0
    add esi, eax
nobranch0:
    NEXT

defprimitive 'branch',branch,1
    lodsd
    add esi, eax
    NEXT

defprimitive '>number',tonumber,1
    pop edi                 ; string
    pop ecx                 ; string length
    xor ebx, ebx
    push esi                ; backup esi
    mov esi, 1
tonum_loop:
    xor eax, eax
    mov al, [edi + ecx - 1]
    cmp al, '0'
    jb tonum_nan
    cmp al, '9'
    ja tonum_nan
    sub al, 48
    mul esi
    add ebx, eax
    mov eax, esi
    mov edx, 10
    mul edx
    mov esi, eax
    loop tonum_loop
    pop esi
    push ebx
    push TRUE
    NEXT
tonum_nan:    
    pop esi
    push ebx
    push FALSE
    NEXT

defprimitive 'adrlit',adrlit,1
    mov eax, xt_lit
    push eax
    NEXT

defprimitive ',',comma,1
    pop eax
    mov edi, [here]
    stosd
    mov [here], edi
    NEXT

defprimitive 'here',here,1
    mov eax, [here]
    push eax
    NEXT
    
defprimitive '>r', rpush,1
    pop eax
    mov [ebp], eax
    add ebp, CELLS
    NEXT
    
defprimitive 'r>', rpop,1
    sub ebp, CELLS
    push dword [ebp]
    NEXT    

defprimitive 'i',i,1                ; gets loop variable from return stack
    push dword [ebp - 1 * CELLS]
    NEXT    

defprimitive 'rswap',rswap,1
    mov eax, [ebp - CELLS]
    mov ebx, [ebp - 2 * CELLS]
    mov [ebp - 2 * CELLS], eax
    mov [ebp - CELLS], ebx
    NEXT

defprimitive 'r2dup',r2dup,1
    mov eax, [ebp - CELLS]
    mov ebx, [ebp - 2 * CELLS]
    mov [ebp], ebx
    add ebp, CELLS
    mov [ebp], eax
    add ebp, CELLS        
    NEXT

defprimitive 'create',create,1
    pop eax                     ; word name
    pop edx                     ; word length
    push esi
    mov esi, eax
    mov edi, [here]             ; beginning of the new dictionary entry
    add edi, 4
    mov eax, [LAST_WORD]        
    mov [LAST_WORD], edi        ; update LAST_WORD to this word
    stosd                       ; set link to previous LAST_WORD
    mov eax, edx                
    stosd                       ; write length  
    mov ecx, edx
    rep movsb                   ; write name
    mov eax, 1                  
    stosd                       ; write word mode  
    mov eax, ENTERCOL           
    stosd                       ; write codeword 
    mov [here], edi             ; update new here
    pop esi
    NEXT
    
defprimitive ';',semicolon,IMMEDIATE
    mov dword [state], MODE_INTERPRET
    mov edi, [here]
    mov eax, EXITCOL
    stosd
    mov [here], edi
    NEXT    

defprimitive 'execute',execute,1
    pop eax
    jmp [eax]

defprimitive 'word',word,1
    push esi
    mov esi, input_buffer
    mov eax, [input_index]
    add esi, eax
    mov ebx, [input_size]
    cmp eax, ebx
    jae word_end_of_input
word_trim:
    lodsb
    inc dword [input_index]
    cmp al, ' '
    je word_trim
    cmp al, 10    
    je word_trim
    cmp al, 13
    je word_trim
    cmp al, 9
    je word_trim            
    lea ebx, [esi - 1]  ; word start
word_next_char:
    lodsb
    inc dword [input_index]
    cmp al, ' '
    je word_boundary
    cmp al, 10
    je word_boundary
    cmp al, 13
    je word_boundary
    cmp al, 9
    je word_boundary        
    jmp word_next_char
word_boundary:    
    sub esi, ebx  ; esi points to word end  
    mov edi, esi  ; calculate length
    dec edi
    pop esi    
    push edi      ; length of word
    push ebx      ; beginnig of word
    NEXT
word_end_of_input:
    pop esi
    push 0
    NEXT

defword ':',colon,1
    dd xt_lit, MODE_COMPILE, xt_state, xt_store
    dd xt_word
    dd xt_create
    dd EXITCOL
    
defprimitive 'immediate',immediate,1
    mov edi, [LAST_WORD]
    add edi, CELLS
    mov eax, [edi]
    add edi, eax
    add edi, CELLS
    mov eax, IMMEDIATE
    stosd
    NEXT
    
FINAL_WORD:
defprimitive 'find',find,1
    pop edx                 ; word to be found
    pop ebx                 ; word length to be found
    push esi                ; backup esi
    mov eax, [LAST_WORD]
find_loop:
    test eax, eax
    jz not_found
    cmp ebx, [eax + CELLS]
    jnz try_next_word
    lea esi, [eax + 2 * CELLS]
    mov edi, edx  
    mov ecx, ebx
    repz cmpsb
    je found
try_next_word:
    mov eax, [eax]          ; step back to previous dictionary entry
    jmp find_loop
not_found:
    pop esi
    push 0
    NEXT
found:
    pop esi
    add eax, CELLS          ; get xt
    mov ebx, [eax]
    add eax, CELLS
    add eax, ebx
    mov ebx, [eax]          ; word mode
    add eax, CELLS
    push eax                ; xt of word
    push ebx                ; mode of word
    NEXT
    
ENTERCOL:
    mov [ebp], esi
    add ebp, CELLS
    add eax, CELLS
    mov esi, eax
    NEXT
    
EXITCOL:
    dd EXITCOL + CELLS
    sub ebp, CELLS
    mov esi, [ebp]
    NEXT

section .data

REPL:                                          ; this is the outer interpreter implemented in binary forth
REPL_loop:
    dd xt_word                                 ; read next word, check end of input
    dd xt_dup, xt_branch0
    dd end_of_input - $ - CELLS
    dd xt_2dup
    dd xt_find                                 ; returns 0 if not found (xt, mode) otherwise. Mode is either -1 (immediate) or +1
    dd xt_dup
    dd xt_branch0
    dd not_found_in_dictionary - $ - CELLS
    dd xt_branch1                              ; if immediate word then interpet regardless of state
    dd (interpret - $ - CELLS)
    dd xt_state, xt_fetch                      ; if non immediate word, interpret or compile depending on state    
    dd xt_branch0
    dd interpret - $ - CELLS
    dd xt_nip, xt_nip                          
    dd xt_comma                                ; compile the xt into the dictionary
    dd xt_branch
    dd REPL_loop - $ - CELLS
interpret: 
    dd xt_nip, xt_nip                          
    dd xt_execute
    dd xt_branch
    dd REPL_loop - $ - CELLS
not_found_in_dictionary:
    dd xt_drop
    dd xt_tonumber
    dd xt_branch0
    dd unknown_word - $ - CELLS
    dd xt_state, xt_fetch, xt_branch0          ; check state
    dd REPL_loop - $ - CELLS                   ; we're in interpret mode, number is already on the stack
    dd xt_adrlit, xt_comma, xt_comma           ; we're in compile mode, compile a literal number
    dd xt_branch
    dd REPL_loop - $ - CELLS
end_of_input:
    dd xt_abort
unknown_word:
    dd xt_lit, '?', xt_emit
    dd xt_lit, 10, xt_emit
    dd xt_abort

STACK_ORIG   dd 0
var0         dd 0
state        dd MODE_INTERPRET
LAST_WORD    dd FINAL_WORD

input_buffer:
    db  ': -rot rot rot ;'                                              ,13,10
    db  ': 0= 0 = ; : 1+ 1 + ; : 1- 1 - ;'                              ,13,10
    db  ''                                                              ,13,10                        
    db  ': if'                                                          ,13,10
    db  '       lit branch0 ,'                                          ,13,10
    db  '       here >r'                                                ,13,10
    db  '       0 ,'                                                    ,13,10
    db  '       rswap ; immediate'                                      ,13,10
    db  ': else'                                                        ,13,10
    db  '       rswap'                                                  ,13,10 
    db  '       lit branch , here >r , 0 ,'                             ,13,10
    db  '       rswap'                                                  ,13,10
    db  '       r> dup'                                                 ,13,10
    db  '       here swap - cells -'                                    ,13,10
    db  '       swap !'                                                 ,13,10
    db  '       rswap ; immediate'                                      ,13,10                                
    db  ''                                                              ,13,10                        
    db  ': then'                                                        ,13,10
    db  '       rswap'                                                  ,13,10
    db  '       r> dup'                                                 ,13,10
    db  '       here swap - cells -'                                    ,13,10
    db  '       swap ! ; immediate'                                     ,13,10
    db  ''                                                              ,13,10                    
    db  ': /mod 2dup % -rot / ;'                                        ,13,10
    db  ': . '                                                          ,13,10    
    db  '       10 /mod dup 0= if'                                      ,13,10    
    db  '           drop 48 + emit'                                     ,13,10            
    db  '       else'                                                   ,13,10        
    db  '          . 48 + emit'                                         ,13,10            
    db  '       then ;'                                                 ,13,10            
    db  ''                                                              ,13,10                    
    db  ': do'                                                          ,13,10
    db  '       lit >r , lit >r , lit rswap ,'                          ,13,10
    db  '       here >r rswap'                                          ,13,10
    db  '   ; immediate'                                                ,13,10    
    db  ''                                                              ,13,10                    
    db  ': loop'                                                        ,13,10
    db  '       lit r> , lit 1+ , lit >r ,'                             ,13,10
    db  '       lit r2dup , lit r> , lit r> ,'                          ,13,10
    db  '       lit < , lit branch1 ,'                                  ,13,10
    db  '       rswap r> here - cells - ,'                              ,13,10
    db  '       lit r> , lit r> , lit drop , lit drop ,'                ,13,10        
    db  '   ; immediate'                                                ,13,10                
    db  ''                                                              ,13,10
    db  ': emit-fizz 122 122 105 102 4 0 do emit loop ;'                ,13,10
    db  ': emit-buzz 122 122 117 98 4 0 do emit loop ;'                 ,13,10    
    db  ''                                                              ,13,10    
    db  ': fizzbuzz'                                                    ,13,10
    db  '       dup 15 % 0= if'                                         ,13,10
    db  '           drop emit-fizz emit-buzz'                           ,13,10
    db  '       else'                                                   ,13,10
    db  '           dup 5 % 0= if'                                      ,13,10
    db  '               drop emit-buzz'                                 ,13,10
    db  '           else'                                               ,13,10
    db  '               dup 3 % 0= if'                                  ,13,10
    db  '                   drop emit-fizz'                             ,13,10
    db  '               else'                                           ,13,10
    db  '                   .'                                          ,13,10
    db  '               then'                                           ,13,10
    db  '           then'                                               ,13,10
    db  '       then ;'                                                 ,13,10
    db  ''                                                              ,13,10
    db  ': fizzbuzz-sequence'                                           ,13,10
    db  '       do i fizzbuzz 32 emit loop ; '                          ,13,10    
    db  ''                                                              ,13,10    
    db  '16 1 fizzbuzz-sequence 10 emit '

input_size   dd $ - input_buffer
input_index  dd 0
here         dd $
dictionary:  times 8192 db 0
RSTACK:      times 8192 db 0 ; return stack
