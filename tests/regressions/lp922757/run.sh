#!/bin/bash 


##
#
# lp:922757
# https://bugs.launchpad.net/codership-mysql/+bug/922757
#
# BUG BACKGROUND:
#
# Foreign key constrainst were taken in consideration so that both parent
# and child key were populated in cert index, i.e. they were recorded as 
# write access for both tables.
# This caused major performance issues due to unnecessary cert failures.
# A general use case has it that one parent table is referenced from many 
# child tables. Transactions updating such separate child rows had conflciting 
# write sets in the parent reference and caused a big number of certification
# aborts.
# 
# TEST SETUP:
#
# This test starts two nodes to play with.
# A child table - parent table pair is created and populated with rows
# so that we have only one parent row and several child rows referencing 
# the parent.
# 
#
# TEST PROCESSES:
#
# Test creates several update processes updating separate child table rows
# updater:   keeps on updating same child table with altering values
#
# SUCCESS CRITERIA
#
# If bug is present, the update process will encounter many deadlocks
# due to cert failures
#
declare -r DIST_BASE=$(cd $(dirname $0)/../..; pwd -P)
TEST_BASE=${TEST_BASE:-"$DIST_BASE"}

. $TEST_BASE/conf/main.conf
declare -r SCRIPTS="$DIST_BASE/scripts"
. $SCRIPTS/jobs.sh
. $SCRIPTS/action.sh
. $SCRIPTS/kill.sh
. $SCRIPTS/misc.sh

echo "##################################################################"
echo "##             regression test for lp:922757"
echo "##################################################################"
echo "stopping node0, node1..."
../../scripts/command.sh stop_node 0
../../scripts/command.sh stop_node 1
echo
echo "starting node0, node1..."
../../scripts/command.sh start_node "-d -g gcomm://" 0
../../scripts/command.sh start_node "-d -g $(gcs_address 1)" 1

MYSQL="mysql --batch --silent --user=$DBMS_TEST_USER --password=$DBMS_TEST_PSWD --host=$DBMS_HOST test "

declare -r port_0=$(( DBMS_PORT ))
declare -r port_1=$(( DBMS_PORT + 1))

declare -r ROUNDS=10000
declare -r ERROR_LIMIT=10
declare success=0
declare err_cnt=0
declare ok_cnt=0

#######################
#       Processes
########################
updater()
{
    local key=$1
    local port=$2
    local errors=0

    echo "updater, key: $key, port: $port starting"

    for (( i=1; i<$ROUNDS; i++ )); do
	fk=$(( $i % 2 ))
	$MYSQL --port=$port -e "UPDATE test.lp922757child set fk=$fk WHERE pk=$key" 2>&1 > /tmp/lp922757.out 
	ret=$?

	if (( $ret != 0 )); then
	    echo "UPDATE failed, ret=$ret key=$key round=$i "
	    cat /tmp/lp922757.out
	    success=1
            errors=$(( $errors + 1 ))
            err_cnt=$(( $err_cnt + 1 ))
	else
	    ok_cnt=$(( $ok_cnt + 1 ))
	fi

       [ $errors -gt $ERROR_LIMIT ]  && echo "update STOPPED, key=$key" && exit 1
    done
    echo "updater, key: $key, port: $port ending"
}

#######################
#       Main, init
########################

echo "Creating database..."
$MYSQL --port=$port_0  -e 'DROP TABLE IF EXISTS test.lp922757child'
$MYSQL --port=$port_0  -e 'DROP TABLE IF EXISTS test.lp922757parent'

$MYSQL --port=$port_0  -e 'CREATE TABLE test.lp922757parent(pk int primary key) engine=innodb'
$MYSQL --port=$port_0  -e 'CREATE TABLE test.lp922757child(pk int primary key, fk int, v int, foreign key (fk) references test.lp922757parent(pk)) engine=innodb'

$MYSQL --port=$port_0 -e 'INSERT INTO test.lp922757parent(pk) VALUES (0)'
$MYSQL --port=$port_0 -e 'INSERT INTO test.lp922757parent(pk) VALUES (1)'

$MYSQL --port=$port_0 -e 'INSERT INTO test.lp922757child(pk,fk,v) VALUES (1,1,0)'
$MYSQL --port=$port_0 -e 'INSERT INTO test.lp922757child(pk,fk,v) VALUES (2,1,0)'
$MYSQL --port=$port_0 -e 'INSERT INTO test.lp922757child(pk,fk,v) VALUES (3,1,0)'
$MYSQL --port=$port_0 -e 'INSERT INTO test.lp922757child(pk,fk,v) VALUES (4,1,0)'
$MYSQL --port=$port_0 -e 'INSERT INTO test.lp922757child(pk,fk,v) VALUES (5,1,0)'
$MYSQL --port=$port_0 -e 'INSERT INTO test.lp922757child(pk,fk,v) VALUES (6,1,0)'
$MYSQL --port=$port_0 -e 'INSERT INTO test.lp922757child(pk,fk,v) VALUES (7,1,0)'
$MYSQL --port=$port_0 -e 'INSERT INTO test.lp922757child(pk,fk,v) VALUES (8,1,0)'
$MYSQL --port=$port_0 -e 'INSERT INTO test.lp922757child(pk,fk,v) VALUES (9,1,0)'
$MYSQL --port=$port_0 -e 'INSERT INTO test.lp922757child(pk,fk,v) VALUES (10,1,0)'


#######################
#       Phase 1
########################
echo
echo "### Phase 1, launch updaters"
echo

updater 1  $port_0 &
declare p1=$!

updater 2  $port_1 &
declare p2=$!

updater 3  $port_0 &
declare p3=$!

updater 4  $port_1 &
declare p4=$!

updater 5  $port_0 &
declare p5=$!

updater 6  $port_1 &
declare p6=$!

updater 7  $port_0 &
declare p7=$!

updater 8  $port_1 &
declare p8=$!

updater 9  $port_0 &
declare p9=$!

updater 10  $port_1 &
declare p10=$!

echo "waiting load to end (PIDs $p1 $p2 $p3 $p4 $p5 $p6 $p7 $p8 $p9 $p10)"
wait

echo
echo "total failed   : $err_cnt"
echo "total succeeded: $ok_cnt"
echo
echo 
echo "Processlist now:"
$MYSQL --port=$port_0 -e 'SHOW PROCESSLIST'
echo
#######################
#       Cleanup
########################
$MYSQL --port=$port_0 -e 'DROP TABLE test.lp922757child'
$MYSQL --port=$port_0 -e 'DROP TABLE test.lp922757parent'

../../scripts/command.sh stop_node 0
../../scripts/command.sh stop_node 1

exit $success