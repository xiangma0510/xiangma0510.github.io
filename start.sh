#!/bin/bash

PORT=30000

open http://localhost:$PORT ;
docsify s -p $PORT
