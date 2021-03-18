from math import *
import os

clear = lambda: os.system('clear')

N = 32
I = 4

flags = [ False, True, False, False, False, False, False ]
circuit = [[], [], [], [], [], [], []]
to_place = "GG"

def print_circuit():
    global circuit

    clear()
    print(" ", " ", end="\t")
    for j in range(N-1, -1, -1):
        if (j + 1) % I == 0:
            print(j + 1, end="\t")

    print()

    for i in range(1, int(log2(N)) + 1, 1):
        print(i, ")", end="\t")
        for j in range(N-1, -1, -1):
            if (j + 1) % I == 0:
                print(circuit[i][j], end="\t")

        print()


for i in range(1, int(log2(N)) + 1, 1):
    for j in range(0, N):
        circuit[i].append("||")

print_circuit()

for j in range (1, N + 2, 1):

    prev_index = j

    for i in range(1, int(log2(N)) + 1, 1):
        
        flags[i] ^= True
        if not flags[i]:
            break
        
        n_fnc = 2**(i-1)
        for k in range(0, n_fnc):
            #print(prev_index + k, end=" -> ", flush=True)
            
            if (prev_index + k) % I != 0 and i > 1:
                continue

            if i > 1 and circuit[i-1][prev_index-1 -1] == "||":
                raise Exception("Sta cosa funziona na volta si e 10 no, manca roba a " + str(i - 1) + "-" + str(prev_index - 1))


            circuit[i][prev_index + k - 1] = to_place + "[" + str(prev_index-1) + "]"
            print_circuit()

        prev_index += (k + 1)
        
        if i == int(log2(N)):
            to_place = "PG"


    #print()

