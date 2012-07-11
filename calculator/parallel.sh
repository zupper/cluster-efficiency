#!/bin/bash

# This script estimates the total energy usage of EEE-enabled switches for
# the performing of a specific task in a cluster environment. The output of
# this script is intended to aid the decision-making process of a workflow
# scheduler in a cluster environment.
#
# The total energy is dependend on multiple parameters (explained below)

# ===================== START OF USER-SUPPLIED DATA =====================

# The number of available nodes
# * User-supplied
NODES=16

# The average pwoer consumption of a node when busy (in watts)
# * User-supplied
NODEPOWER=65

# Which profile to use for energy consumption values
# * User-supplied
SWITCH="huawei"

# Usable ports per switch
# * User-supplied
PORTSPERSWITCH=23

# The total time needed to complete the task on one node (in minutes)
# * User-supplied
TOTALTIME=1

# Communication overhead for adding a node (in minutes)
# * User-supplied
COMMOVERHEAD=0.01

# Which speeds to consider (possible speeds: 50, 100, 150, ..., 1000)
# * User-supplied
SPEEDS="250"

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

RESULTSDIR="results"
RECOMMENDFILE="$RESULTSDIR/recommendation"
AVGBASE=`awk '{ sum+=$2 } END { print sum/NR }' < $BASELINE`

(rm -rf $RESULTSDIR && mkdir $RESULTSDIR) || (echo "Could not create results dir!" && exit 1)
touch $RECOMMENDFILE

for SPEED in $SPEEDS; do
	echo Working with ${SPEED}M
	
	TMPRECOMMEND="/tmp/recommend-$SPEED"
	rm -f $TMPRECOMMEND
	touch $TMPRECOMMEND
	
	FILE="$PROFILEDIR/iperf-link_util-${SPEED}M"
	AVG=`awk '{sum+=$2} END { print sum/NR}' < $FILE`
	
	PERPORT=$(echo – | awk "{print ($AVG - $AVGBASE)/$BASELINEPORTS}")
	
	RESFILE=$RESULTSDIR/power-vs-time-at-${SPEED}M.dat
	echo "Ports Energy Time TimePower" > $RESFILE
	
	MINPOWER=999999
	SECONDMIN=999999
	
	nodescount=1
	# Use the variables below to estimate for 2^x number of nodes
	#counter=0
	#nodescount=$((2**counter))
	while [ $nodescount -le $NODES ]; do
		# How many switches are needed to get $counter usable ports?
		SWCOUNT=$((nodescount/PORTSPERSWITCH + 1))
		
		# We estimate what the switch power usage will be for $counter ports at this $SPEED (in W)
		POWER=$(echo – | awk "BEGIN {print $nodescount * $PERPORT + $AVGBASE * $SWCOUNT}")
		TIMETASK=$(echo – | awk "{print $TOTALTIME / $nodescount + ($COMMOVERHEAD * ($nodescount - 1))}")
		
		# Time-power product (gives energy consumed in Wh)
		TPPRODUCT=$(echo – | awk "{print (($TIMETASK / 60) * $POWER)}")
		
		COMPUTEPOWER=$((nodescount * NODEPOWER))
		
		# Time-(switch/server)-power product
		TPCPRODUCT=$(echo – | awk "{print (($TIMETASK / 60) * ($POWER + $COMPUTEPOWER))}")
		
		echo $nodescount $POWER $TIMETASK $TPPRODUCT $BANDWIDTH $COMPUTEPOWER $TPCPRODUCT >> $RESFILE
		echo $TPCPRODUCT $nodescount >> $TMPRECOMMEND
		
		nodescount=$((nodescount + 1))
		# Use the variables below to estimate for 2^x number of nodes
		#counter=$((counter+1))
		#nodescount=$((2**counter))
	done
	
	sort -n $TMPRECOMMEND > /tmp/tempfile && mv /tmp/tempfile $TMPRECOMMEND
	
	echo "Speed: ${SPEED}M" >> $RECOMMENDFILE
	
	MINPOWER=`sed -n 1p $TMPRECOMMEND | sed -e 's/ .*$//'`
	MINNODES=`sed -n 1p $TMPRECOMMEND | sed -e 's/^.* //'`
	echo "    Nodes:" $MINNODES, Power: $MINPOWER >> $RECOMMENDFILE
	
	RECOMENDLINES=`cat $TMPRECOMMEND | wc -l`
	
	if [ $RECOMENDLINES -ge 3 ]; then
		counter=2
		while [ $counter -le 3 ]; do
			THISPOWER=`sed -n ${counter}p $TMPRECOMMEND | sed -e 's/ .*$//'`
			THISNODES=`sed -n ${counter}p $TMPRECOMMEND | sed -e 's/^.* //'`
		
			if [ $THISNODES -gt $MINNODES ]; then
				echo "    Nodes:" $THISNODES, Power: $THISPOWER >> $RECOMMENDFILE
				counter=$((counter + 1))
			fi
		done
	fi
	
	# cleanup
	rm -f $TMPRECOMMEND /tmp/tempfile
done

# ======================== CALCULATION FINISHED. PLOTTING FOLLOWS ==========================

PLOTCMDS="reset;\
set output '${PLOTSFILE}';\
set terminal pdf;\
set grid;\
set xlabel 'Number of nodes';\
set ylabel 'Time needed for task (minutes)';\
set style fill solid border rgb 'black';\
set y2tics 2;\
set xtics 2;\
set xtics font '0,5';\
set auto x;\
set auto y;\
set key outside below center horizontal;\
set style data lines;\
"

for BANDWIDTH in $SPEEDS; do
	DATA="results/power-vs-time-at-${BANDWIDTH}M.dat"
	THISPLOT="set title 'Energy Consumption of Switch(es) and Time Distribution (${BANDWIDTH}Mbit)';\
		set y2label 'Energy Consumption of Switch (W)';\
		plot '${DATA}' using 3 title 'Time' linewidth 3 axes x1y1, \
		'' using 2 title 'Switches Energy (Watt)' linewidth 3 linecolor 3 axes x1y2;\
		
		set y2tics 100;\
		set title 'Compute Nodes Energy Consumed (${BANDWIDTH}Mbit)';\
		set y2label 'Energy Consumption of Compute Nodes (W)';\
		plot '${DATA}' using 3 title 'Time' linewidth 3 axes x1y1, \
		'' using 5 title 'Compute Nodes Energy (Watt)' linewidth 3 linecolor 3 axes x1y2;\
		\
		set grid;\
		set auto y;\
		set y2label '';\
		set y2tics 0;\
		\
		set title 'Time Distribution Estimation';\
		set ylabel 'Time Needed for Task (minutes)';\
		plot '${DATA}' using 3 title 'Time' linewidth 3 axes x1y1; \
		\
		set title 'Switch(es) Energy Estimation (${BANDWIDTH}M)';\
		set ylabel 'Switch(es) Energy Consumption (W)';\
		plot '${DATA}' using 2 title 'Switches Energy (Watt)' linewidth 3 linecolor 3 axes x1y1;\
		\
		set title 'Total Switch(es) Energy Consumed for Task (${BANDWIDTH}Mbit)';\
		set ylabel 'Total Energy Consumed for Task (Switch) (Wh)';\
		plot '${DATA}' using 4 title 'Swith(es) Energy Consumption' linestyle 3 linewidth 3 axes x1y1;\
		\
		set title 'Total Energy Consumed for Task (${BANDWIDTH}Mbit)';\
		set ylabel 'Total Energy Consumed for Task (Wh)';\
		plot '${DATA}' using 6 title 'Energy Consumption' linestyle 3 linewidth 3 axes x1y1;\
"	
	PLOTCMDS=$PLOTCMDS$THISPLOT
done

# DEBUG
#echo $PLOTCMDS
(gnuplot -e "$PLOTCMDS" && echo Created plots) || (echo Failed to create plots && exit 1)

echo
echo Recommendations:
cat $RECOMMENDFILE

exit 0

