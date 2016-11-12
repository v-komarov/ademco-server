#!/bin/bash

cd /home/vak/django/server/ademco-server/

erl <<EOF
ademco:start().
EOF
