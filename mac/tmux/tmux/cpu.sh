#!/bin/bash
cpu=$(top -l 1 | grep "CPU usage" | awk '{print int($3+$5)}')
cpu="#[bg=brightblue,fg=black] CPU:$cpu% #[default]"
echo $cpu