#include <stdio.h>
#include <cstdlib>
#include <iostream>
#include <fstream>
#include <iomanip>
#include <unistd.h>
#include <sys/stat.h>

using namespace std;

#define BYTES_PER_LINE 32

int main(int argc, char **argv)
{
    int ch;
    while ((ch = getopt(argc, argv, "h?")) != -1) {
        switch(ch) {
        case 'h':
        case '?':
        default:
            cout << "Usage: bin2ld <start-address> <binary-file>" << std::endl;
            exit(1);
        }
    }

    unsigned long addr = strtoul(argv[1],0,0);
    const char* filename = argv[2];
    struct stat buf;
    if (stat(filename, &buf)) {
        cerr << "Cannot stat input file: " << filename << endl;
        exit(1);
    }
    unsigned long highaddr = addr + buf.st_size;
    if (highaddr > 0x10000) {
        cerr << "Address range exceeds a 16-bit address space" << endl;
        exit(1);
    }
    if (highaddr > 0x4000) {
        cerr << "Address range exceeds a 16KB RAM" << endl;
        exit(1);
    }

    std::ifstream fin(filename, ios_base::in | ios_base::binary);
    int bytes_left_on_line;
    unsigned x;
    cout << hex << uppercase << setfill('0');

    if (!fin) {
        cerr << "problem with fin on opening" << endl;
        goto finish;
    }

    x = fin.get();
    if (x == EOF)
        goto finish;

 startline:
    bytes_left_on_line = BYTES_PER_LINE;
    cout << setw(4) << addr << ':';
    addr += BYTES_PER_LINE;
 byte:
    if (!bytes_left_on_line) {
        cout << endl;
        goto startline;
    }
    cout << ' ' << setw(2) << x;
    --bytes_left_on_line;
    x = fin.get();
    if (x == EOF) {
        cout << endl;
        goto finish;
    }
    goto byte;

 finish:
    ;
}
