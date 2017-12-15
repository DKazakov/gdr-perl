#!/bin/bash

MODULES=(
# Global
    'local::lib'
# GDR
    'LWP::UserAgent'
    'JSON::XS'
    'GD::Graph'
    'Term::ReadKey'
    'Math::Round'
    'LWP::Protocol::https'
)

for module in ${MODULES[@]}
do
    echo "install ${module}"
    cpan -i ${module}
    if [ $? != 0 ]
    then
        echo "ERROR!!!"
        exit 1
    fi
done
