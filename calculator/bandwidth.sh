#!/bin/bash

# ===================== START OF USER-SUPPLIED DATA =====================

# The number of used nodes
# * User-supplied
NODES=2

# The amount of data to transfer (MB)
# * User-supplied
DATA=97280

# Usable ports per switch
# * User-supplied
PORTSPERSWITCH=23

# Which profile to use for energy consumption values
# * User-supplied
SWITCH="huawei"

# The total time needed to complete the task on one node (in minutes)
# * User-supplied
TOTALTIME=55

# Filename of the plots file
# * User-supplied
PLOTSFILE="out.pdf"

# ====================== END OF USER-SUPPLIED DATA ======================

# ===================== START OF KNOWLEDGE BASE DATA ====================
# Baseline file -- containing the power consumption (in W) of the idle switch over time
# * Knowledge base
BASELINE="$SWITCH/baseline.gbit.eee.dat"

# Directory containing the power profile of the switch at different transmission speeds
# * Knowledge base
PROFILEDIR=$SWITCH

# The number of ports connected to establish the baseline
# * Knowledge base
BASELINEPORTS=22

# ====================== END OF KNOWLEDGE BASE DATA =====================

float_test() {
     echo | awk 'END { exit ( !( '"$1"')); }'
}

SPEEDS="50 100 150 200 250 300 350 400 450 500 550 600 650 700 750 800 850 900 950 1000"
RESULTSDIR="results"
AVGBASE=`awk '{ sum+=$2 } END { print sum/NR }' < $BASELINE`

(rm -rf $RESULTSDIR && mkdir $RESULTSDIR) || (echo "Could not create results dir!" && exit 1)

# How many switches are needed to get $counter usable ports?
SWCOUNT=$((NODES/PORTSPERSWITCH + 1))
RESFILE=$RESULTSDIR/power-vs-band.dat

for SPEED in $SPEEDS; do
	echo Working with ${SPEED}M
	
	DATAMBIT=$((DATA*8))
	TIMENEEDED=$(echo – | awk "BEGIN {print $DATAMBIT / ($SPEED * 60)}")
	
	float_test "$TIMENEEDED > $TOTALTIME" && echo ${SPEED}Mbit will not work && continue
	
	IDLETIME=$(echo – | awk "BEGIN {print $TOTALTIME - $TIMENEEDED }")
	IDLEPOWER=$(echo – | awk "BEGIN {print ($IDLETIME / 60) * $AVGBASE }")
	
	FILE="$PROFILEDIR/iperf-link_util-${SPEED}M"
	AVG=`awk '{sum+=$2} END { print sum/NR}' < $FILE`
	
	PERPORT=$(echo – | awk "{print ($AVG - $AVGBASE)/$BASELINEPORTS }")
	
	# We estimate what the switch power usage will be for $counter ports at this $SPEED (in W)
	POWER=$(echo – | awk "BEGIN {print $NODES * $PERPORT + $AVGBASE * $SWCOUNT }")
	TPPRODUCT=$(echo – | awk "{print (($TIMENEEDED / 60) * $POWER) }")
	
	echo $SPEED $POWER $TIMENEEDED $TPPRODUCT $IDLEPOWER $IDLETIME >>$RESFILE
done

# ======================== CALCULATION FINISHED. PLOTTING FOLLOWS ==========================

PLOTCMDS="reset;\
set output '${PLOTSFILE}';\
set terminal pdf;\
set grid;\
set xlabel 'Speed (mbps)';\
set ylabel 'Time needed for task (minutes)';\
set style fill solid border rgb 'black';\
set y2tics 0.1;\
set xtics 2;\
set xtics font '0,5';\
set auto x;\
set auto y;\
set key outside below center horizontal;\
set style data lines;\
"

DATA="results/power-vs-band.dat"
THISPLOT="set title 'Energy Consumption of Switch(es) and Time Needed (${BANDWIDTH}Mbit)';\
	set y2label 'Energy Consumption of Switch (W)';\
	plot '${DATA}' using 3:xtic(1) title 'Time needed' linewidth 3 axes x1y1, \
	'' using 2 title 'Switch Energy (W)' linewidth 3 linecolor 3 axes x1y2;\
	\
	set grid;\
	set title 'Total Switch Energy Consumed for Task';\
	set ylabel 'Total Switch Energy Consumed for Task (Wh)';\
	set y2label '';\
	set y2tics 0;\
	plot '${DATA}' using 4:xtic(1) title 'Total Switch Energy Consumed' linestyle 3 linewidth 3 axes x1y1;\
"	
PLOTCMDS=$PLOTCMDS$THISPLOT

# DEBUG
#echo $PLOTCMDS
(gnuplot -e "$PLOTCMDS" && echo Created plots) || (echo Failed to create plots && exit 1)

echo
#echo Recommendations:
#cat $RECOMMENDFILE

exit 0

