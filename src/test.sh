#!/bin/bash
source /etc/profile
a="123/456"
b=${a//\//_}".mat"
echo $b
#module load spm12
#spm