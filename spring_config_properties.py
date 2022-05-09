import os
import yaml
import json
import git
import re

# FILE_PATHS ENVs
# '''
# ARCS_FILE_PATH
# ADD_ON_FILE_PATH
# DARMA_LMR_FILE_PATH
# FRP_BATCH_FILE_PATH
# FRP_COMMON_FILE_PATH
# FRP_DB_FILE_PATH
# FRP_LOCATION_FILE_PATH
# IAM_FILE_PATH
# MKT_FILE_PATH
# MEDIATOR_FILE_PATH
# NOTIFICATION_FILE_PATH
# PE_DISCOUNT_FILE_PATH
# PE_ORDER_FILE_PATH
# PE_PAYMENT_FILE_PATH
# PE_TAX_FILE_PATH
# PE_MEDIATOR_FILE_PATH
# PE_BE_FILE_PATH
# RE_FILE_PATH
# HMT_FILE_PATH
# VALIDATE_ADDRESS_FILE_PATH
# ID_SERVICE_FILE_PATH
# RMS_FILE_PATH
# SCM_FILE_PATH
# STOREFRONT_FILE_PATH
# '''

# 
services = [
    "ADD_ON","HMT","SCM","STOREFRONT"
]    # "ARCS","ADD_ON","DARMA_LMR","FRP_BATCH","FRP_COMMON","FRP_DB","FRP_LOCATION",
    # "IAM","MKT","MEDIATOR","NOTIFICATION","PE_DISCOUNT","PE_ORDER","PE_PAYMENT",
    # "PE_TAX","PE_MEDIATOR","PE_BE","RE","HMT","VALIDATE_ADDRESS","ID_SERVICE",
    # "RMS","SCM","STOREFRONT"
# ]

# Change the current working directory
os.chdir('/tmp/spring-cloud-config/')


REDIS_CLUSTER_ENDPOINT=os.environ['REDIS_CLUSTER_ENDPOINT']
KAFKA_CLUSTER_ENDPOINT=os.environ['KAFKA_CLUSTER_ENDPOINT']
REDSHIFT_CLUSTER_ENDPOINT=os.environ['REDSHIFT_CLUSTER_ENDPOINT']
ES_CLUSTER_ENDPOINT=os.environ['ES_CLUSTER_ENDPOINT']

for service in services:
    full_file_path=os.environ[service+'_FILE_PATH']
    
    file_path=re.split(r'(.*/)',full_file_path)[1]
    file_name=re.split(r'(.*/)',full_file_path)[2]

    spring_application_name=re.split(r'(.*-)',file_name)[1]
    
    # open file
    with open(full_file_path, 'r+') as file:
      properties = yaml.safe_load(file)
      file.close()

    # Check for db url
    try:
        # Shared services properties
        rds_endpoint=os.environ[service+'_RDS_ENDPOINT']

        properties['spring']['datasource']['url'] = re.sub('(.*\/)', 'jdbc:postgresql://${DB_HOST:'+rds_endpoint+':5432/', properties['spring']['datasource']['url'])
    except KeyError:
        pass

    # Check for redis url
    try:
        properties['spring']['redis']['host'] = '${REDIS_HOST:'+REDIS_CLUSTER_ENDPOINT+'}'
    except KeyError:
        pass
    
    # Check for kafka url
    try:
        properties['kafka']['server']['address'] = '${KAFKA_SERVER:'+KAFKA_CLUSTER_ENDPOINT+'}'
    except KeyError:
        pass
    
    # Check for ES url
    try:
        properties['elasticsearch']['hosts'] = ES_CLUSTER_ENDPOINT
    except KeyError:
        pass

    # Check for redshift url
    try:
        properties['redshift']['datasource']['url'] = REDSHIFT_CLUSTER_ENDPOINT
    except KeyError:
        pass
    
    # output properties object to file
    dr_file_path=file_path+spring_application_name+'dr.yaml'
    with open(dr_file_path, 'w+') as file:
        yaml.dump(properties, file)
        file.close()

# Commit and push
repo = git.Repo('./')
repo.commit('master')
repo.git.add(update=True)
repo.index.commit("ARGO_WORKFLOW_AUTOMATION: Updating shared services properties for disaster recovery profiles")
origin = repo.remote(name='origin')
origin.push()

