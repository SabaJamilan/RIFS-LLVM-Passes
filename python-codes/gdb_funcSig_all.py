import gdb
import sys
import os
import re

fd=open("func_sig_info.txt", "a")
fd_v1=open("func_sig_v1.csv", "a")
fd_v2=open("func_sig_v2.csv", "a")
fd_v3=open("func_sig_v3.csv", "a")
fd_v4=open("func_sig_v4.csv", "a")
fd_v5=open("func_sig_all.csv", "a")
#fd_v6=open("func_sig_all_pointer_types.csv", "a")


def find_between_r( s, first, last ):
    try:
        start = s.rindex( first ) + len( first )
        end = s.rindex( last, start )
        return s[start:end]
    except ValueError:
        return ""

def execute_output(command):
    # create temporary file for the output
    filename = 'gdb_output_' + str(os.getpid()) + ".out"
    
    # set gdb logging
    gdb.execute("set logging file " + filename)
    gdb.execute("set logging overwrite on")
    gdb.execute("set logging redirect on")
    gdb.execute("set logging on")
    gdb.execute("set pagination off")

    # execute command
    try:
        gdb.execute(command)
    except:
        pass
    
    # restore normal gdb behaviour
    gdb.execute("set logging off")
    gdb.execute("set logging redirect off")
    # read output and close temporary file
    outfile = open(filename, 'r')
    output = outfile.read()
    outfile.close()
    # delete file
    #os.remove(filename)
    # split lines
    output = output.splitlines()
    return output

def search_functions(regex=''):
    # get the functions
    output = execute_output('info functions ' + regex)
    #output = execute_output('info address ' + regex)
    functions = dict()
    deb_funcs = list()

    # extract debugging functions
    for line in output:
        if re.search('\);$', line):
            num_args=0
            fd.write(line+"\n")
   #         print("line: ", line)
            if(len(line)> 0):
                #print("Yes!! ")
                func = line.split('(')[0].split(' ')[-1]
                func = func.replace('*', '')
                #print("func: ", func)
                if(func != ""):
                    #print("func")
                    if len((line.split('(')[0].split('\t')[-1]).split(func))> 0 :
                        #print("No!!")
                        #print("return_type:  ", return_type)
                        return_type= (line.split('(')[0].split('\t')[-1]).split(func)[0]
            else:
                func ="nan"
                #print("nan\n")
                return_type="nan"
            #print("line: ", line,  " return_type: ", return_type)
            deb_funcs.append(func)

            args=find_between_r( str(line), "(", ")" )
            num_args=args.count(',')

            if num_args != 0:
                #print(line)
                fd_v1.write(str(num_args+1)+ "," +return_type+ ","+ func + ","+ args +"\n")
                fd_v2.write(str(num_args+1)+ "," +return_type+ ","+ func + ","+ args +"\n")
                fd_v3.write(func +"\n")
            else:
                if(args != ''):
                    fd_v1.write(str(num_args+1)+ "," +return_type+ ","+ func + ","+ args +"\n")
                    fd_v2.write(str(num_args+1)+ "," +return_type+ ","+ func + ","+ args +"\n")
                    fd_v3.write(func +"\n")
                else:
                    fd_v1.write(str(num_args)+ "," +return_type+ ","+ func +"\n")


            #print("args: ", args)
            args = " " + args
            #print("args_new: ", args_new)
            str1= " int"
            str2= " float"
            str3= "unsigned long"
            str4= "*"
            str5= "size_t"
            
            index = args.find(str1)
            args_loc=[]
            args_type=[]
            loc=0
            int_found=False
            float_found=False
            
            num_float_int_args=0
            num_float_args=0
            num_pointer_args=0
            num_int_args=0
            
            #print("args: ", args)
            for t in args.split(','):
                #print("t: ", t)
                if(t.find(str1) != -1  and t.find(str3) == -1 and t.find(str4) == -1):
                    args_loc.append(loc)
                    args_type.append(t)
                    num_float_int_args += 1
                    num_int_args += 1
                    int_found=True
                if(t.find(str2) != -1 and t.find(str4) == -1) :
                    args_loc.append(loc)
                    args_type.append(t)
                    num_float_int_args += 1
                    num_float_args += 1
                    float_found=True
                if(t.find(str3) != -1 and t.find(str1) == -1 and t.find(str4) == -1):
                    args_loc.append(loc)
                    args_type.append(t)
                    num_float_int_args += 1
                    num_int_args += 1
                    int_found=True
                if(t.find(str4) != -1 and (t.find(str3) == -1 or t.find(str2) == -1 or t.find(str1) == -1)):
                    #print("t: ", t)
                    num_float_int_args += 1
                    args_loc.append(loc)
                    args_type.append(t)
                    num_pointer_args += 1
                if(t.find(str5) != -1  and t.find(str4) == -1 and (t.find(str3) == -1 or t.find(str2) == -1 or t.find(str1) == -1)):
                    num_float_int_args += 1
                    #print("t: ", t)
                    args_loc.append(loc)
                    args_type.append(t)
                    num_int_args += 1
                    int_found=True
                loc += 1


            args_list=[]
            for t in args.split(','):
                    args_list.append(t)

            pin_args_loc=[]
            pin_args_type=[]
            pin_index=0
 
            for a in range(0,len(args_list)):
                #if(args_list[a].find(str1) != -1 or args_list[a].find(str3) != -1 or args_list[a].find(str4) != -1 or  args_list[a].find(str5) != -1):
                #print("args_list[a]: ", args_list[a])
                #print("pin_index: ", pin_index)
                pin_args_loc.append(pin_index)
                pin_args_type.append(args_list[a])
                pin_index += 1


            #if(int_found or float_found):
            if( num_float_int_args > 0):
                fd_v4.write(str(num_args+1)+ "," +return_type+ ","+ func + ","+ args +"\n")
                #fd_v5.write(str(num_args+1)+ "," +str(num_float_int_args)+ ","+ func)
#                if(num_int_args > 0):
                fd_v5.write(func + ","+ str(num_args+1)+"," + str(num_int_args)+ "," + str(num_float_args)+ "," + str(num_pointer_args))
            #fd_v6.write(func + ","+ str(num_args+1)+"," + str(num_int_args)+ "," + str(num_float_args)+ "," + str(num_pointer_args))

                for x in range(0,len(args_loc)):
                        for y in range(0,len(pin_args_loc)):
                            if(pin_args_type[y] == args_type[x] and y == x):
                        #if( pin_args_type[y].find(str4) != -1):
                            #fd_v5.write(","+str(" pointer") + "," + str(args_loc[x])+  "," + str(pin_args_loc[y]))
                            #fd_v5.write(","+str(" pointer") + "," + str(args_loc[x]))
                         #   fd_v5.write(","+str(args_type[x]) + "," + str(args_loc[x]))

                        #else:
                            #fd_v5.write(","+str(args_type[x]) + "," + str(args_loc[x])+  "," + str(pin_args_loc[y]))
                               fd_v5.write(","+str(args_type[x]) + "," + str(args_loc[x]))
                            #fd_v6.write(","+str(args_type[x]) + "," + str(args_loc[x])+  "," + str(pin_args_loc[y]))
               #         fd_v6.write(","+str(args_type[x]) + "," + str(args_loc[x]) )
                fd_v5.write("\n")
                    

    # insert debugging function in dictionary
    for func in deb_funcs:
        if len( execute_output('p ' + func)) > 0:
            addr = execute_output('p ' + func)[0].split(' ')[-2]
        else:
            addr =0
#        addr = int(addr, 16)
        functions[func] = addr


    # insert non debugging functions in dictionary
#    for line in output:
#        if re.search('^0x[0-9a-f]+', line):
#            print("non-debugging function: ", line)
#            func = line.split(' ')[-1]
#            addr = line.split(' ')[0]
#            addr = int(addr, 16)
#            functions[func] = addr

    return functions


trace_functions=search_functions()
fd.close()
fd_v1.close()
fd_v2.close()
fd_v3.close()
fd_v4.close()
fd_v5.close()
gdb.execute('quit')

