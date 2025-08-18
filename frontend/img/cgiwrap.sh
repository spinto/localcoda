#!/bin/python3
#FastCGI wrapper for data
import os, sys, json, subprocess
from http.client import responses as http_res  # Standard status code descriptions

#CGI functions
def perror(c, d=None):
    """
    Send an HTTP error response in JSON format in a CGI script.
    
    Parameters:
        c (int): HTTP status code (e.g., 404, 500).
        d (str, optional): Description. Defaults to standard if not provided.
    """
    if d is None:
        d = http_res.get(c, "Unknown Error")
    
    # CGI scripts must print the headers first
    print(f"Status: {c} {http_res.get(c, '')}")
    print("Content-Type: application/json\n")
    
    # JSON body
    error_data = {
        "error": {
            "code": c,
            "message": d
        }
    }
    print(json.dumps(error_data))
    sys.exit(0)  # Stop further execution after sending the error
def psuccess(data, c=200):
    """
    Send a successful JSON response in a CGI script.
    
    Parameters:
        data (dict|list|str|int|float|bool): The data to send as JSON.
        c (int, optional): HTTP status code (default 200).
    """
    # CGI scripts must print the headers first
    print(f"Status: {c} {http_res.get(c, '')}")
    print("Content-Type: application/json\n")
    
    # Ensure the data is JSON-serializable
    if isinstance(data,str):
      print(data)
    else:
      print(json.dumps(data))
    sys.exit(0)

#Read URI
path_info=os.environ['PATH_INFO']
path_par=path_info[path_info.find('/ctl/')+5:].split('/',1)
cmd=path_par[0]
arg=path_par[1] if len(path_par)>1 else ''

#Get user and group
req_user=os.environ['X-USER'] if 'X-USER' in os.environ else ''
req_group=os.environ['X-GROUP'] if 'X-GROUP' in os.environ else ''

#Execute command
if cmd=="browse":
  #Sanitize input folder
  arg=os.path.abspath(os.sep+''.join(c for c in arg if c in set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/-_.")))
  tut_basepath=os.environ['TUTORIALS_VOLUME_ACCESS_MOUNT']
  tut_abspath=tut_basepath+arg+os.sep
  tut_splitpath=arg.split(os.sep,101)
  tut_splitpath_len=len(tut_splitpath)
  if tut_splitpath_len>100: perror(400, "path too long")
  if tut_splitpath_len<2: perror(400, "path too short")
  if tut_splitpath[tut_splitpath_len-1]=="": del tut_splitpath[tut_splitpath_len-1]

  #Check if the folder exists and is not a scenario folder
  if not os.path.isdir(tut_abspath) or os.path.isfile(tut_abspath+"index.json"): perror(404, "path not found")

  #Trasverse the path till the current folder, checking permissions and loading titles, if any, end up with the last part of the path
  st_path=[]
  cur_path=""
  st={}
  for el in tut_splitpath:
    #Path to load
    if el!="": cur_path=cur_path+os.sep+el

    #Load the definition in the previous structure file (if present)
    if 'items' in st:
      st_prev=next((i for i in st["items"] if i.get("path") == el), {})
    else:
      st_prev={}

    #Check permissions in the old structure file (if present)
    if req_user and ('permission' in st_prev) and not ( ( 'groups' in st_prev['permission'] and req_group in st_prev['permission']['groups'] ) or ( 'users' in st_prev['permission'] and req_user in st_prev['permission']['users'] ) ): perror(403,f"Access forbidden to {cur_path}")

    #Load a structure.json file, if present
    structfile=tut_basepath+cur_path+os.sep+"structure.json"
    if os.path.isfile(structfile):
      try:
        with open(structfile,"r", encoding="utf-8") as f:
          st=json.load(f)
      except json.JSONDecodeError as e:
        perror(200,f"Invalid structure: {e}")
      except OSError as e:
        perror(500,f"Cannot read file. {e}")
    else:
      st={}
    
    #Check permissions in the current structure file (if present)
    if req_user and 'permission' in st and not ( ( 'groups' in st['permission'] and req_group in st['permission']['groups'] ) or ( 'users' in st['permission'] and req_user in st['permission']['users'] ) ): perror(403,f"Access forbidden to {cur_path}")

    #Add title and description, if not present, use the previous, if not present, use the path as title
    if 'title' not in st:
      if 'title' in st_prev:
        st['title']=st_prev['title']
      else:
        st['title']=el
    if 'description' not in st and 'description' in st_prev: st['description']=st_prev['description']
    #Add the path to the path list
    st_path+=[{'title':st['title'],'path':cur_path}]

  #Add the path list to the structure, remove what we do not need from it
  st['paths']=st_path
  if 'permission' in st: del st['permission']

  #If you do not have a list of items in the structure, load it
  if 'items' not in st:
    st['items'] = [{"path": d} for d in next(os.walk(tut_abspath))[1]]

  #Load scenarios titles and descriptions (if not overwritten)
  for d in st['items']:
    #Delete items not needed
    if 'advanced' in d: del d['advanced']
    #Check permissions if set and delete items who do not meet them
    if 'permission' in d:
      if req_user and not ( ( 'groups' in d['permission'] and req_group in d['permission']['groups'] ) or ( 'users' in d['permission'] and req_user in d['permission']['users'] ) ):
        del d
      else:
        del d['permission']
    #If you have a scenario ( index.json ) inside, load its title and/or description if not set
    if os.path.isfile(tut_abspath+d['path']+os.sep+'index.json'):
      d['type']='scenario';
      try:
        with open(tut_abspath+d['path']+os.sep+"index.json","r", encoding="utf-8") as f:
          fv=json.load(f)
      except json.JSONDecodeError as e:
        d['title']=d['path']
        d['description']=f"Invalid JSON: {e}"
        continue
      except OSError as e:
        perror(500,f"Cannot read file. {e}")
      if 'title' not in d: d['title']=fv['title']
      if 'description' not in d: d['description']=fv['description']
    #If you have a tutorial ( structure.json ) inside, load its title and/or description if not set
    elif os.path.isfile(tut_abspath+d['path']+os.sep+'structure.json'):
      d['type']='structure';
      try:
        with open(tut_abspath+d['path']+os.sep+"structure.json","r", encoding="utf-8") as f:
          fv=json.load(f)
      except json.JSONDecodeError as e:
        d['title']=d['path']
        d['description']=f"Invalid JSON: {e}"
        continue
      except OSError as e:
        perror(500,f"Cannot read file. {e}")
      if 'title' not in d: d['title']=fv['title']
      if 'description' not in d: d['description']=fv['description']
    #If we have just sub-directories inside, still this is a structure
    else:
      d['type']='structure';
    #If still title and description is not set, set it to the name of the folder and to an empty string
    if 'title' not in d: d['title']=d['path']
    if 'description' not in d: d['description']=''
  psuccess(st)

elif cmd=="run":
  #Start a new scenario
  #Sanitize input folder
  arg=os.path.abspath(os.sep+''.join(c for c in arg if c in set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/-_.")))
  tut_basepath=os.environ['TUTORIALS_VOLUME_ACCESS_MOUNT']
  tut_abspath=tut_basepath+arg+os.sep
  tut_splitpath=arg.split(os.sep,101)
  tut_splitpath_len=len(tut_splitpath)
  if tut_splitpath_len>100: perror(400, "path too long")
  if tut_splitpath_len<2: perror(400, "path too short")
  if tut_splitpath[tut_splitpath_len-1]=="": del tut_splitpath[tut_splitpath_len-1]
  tut_scenariopath=tut_splitpath[2] if tut_splitpath_len==3 else ""
  tut_scenariopath+=os.sep + 'index.json'
  tut_areaname=tut_splitpath[1]

  #Check if the folder exits
  if not os.path.isdir(tut_abspath) or not os.path.isfile(tut_abspath+"index.json"): perror(404, "path not found")

  #Check if you have the rights to start this (transverse all the path to do so)
  cur_path=""
  st={}
  ar=None
  for el in tut_splitpath:
    #Path to load
    if el!="": cur_path=cur_path+os.sep+el

    #Load the definition in the previous structure file (if present)
    if 'items' in st:
      st_prev=next((i for i in st["items"] if i.get("path") == el), {})
      #The first structure file you see is the area. We load it and keep it for the later advanced paramters
      if ar is None: ar=st_prev
    else:
      st_prev={}

    #Check permissions in the old structure file (if present)
    if req_user and ('permission' in st_prev) and not ( ( 'groups' in st_prev['permission'] and req_group in st_prev['permission']['groups'] ) or ( 'users' in st_prev['permission'] and req_user in st_prev['permission']['users'] ) ): perror(403,f"Access forbidden to {cur_path}")

    #Load a structure.json file, if present
    structfile=tut_basepath+cur_path+os.sep+"structure.json"
    if os.path.isfile(structfile):
      try:
        with open(structfile,"r", encoding="utf-8") as f:
          st=json.load(f)
      except json.JSONDecodeError as e:
        perror(200,f"Invalid structure: {e}")
      except OSError as e:
        perror(500,f"Cannot read file. {e}")
    else:
      st={}

    #Check permissions in the current structure file (if present)
    if req_user and 'permission' in st and not ( ( 'groups' in st['permission'] and req_group in st['permission']['groups'] ) or ( 'users' in st['permission'] and req_user in st['permission']['users'] ) ): perror(403,f"Access forbidden to {cur_path}")

  #Load scenario to check if it is valid
  try:
    with open(tut_abspath+"index.json","r", encoding="utf-8") as f:
      sf=json.load(f)
  except json.JSONDecodeError as e:
    perror(200,f"Invalid scenario file: {e}")
  except OSError as e:
    perror(500,f"Cannot read file. {e}")

  #Check you have permissions to run the scenario
  if req_user:
   if 'permission' in sf and not ( ( 'groups' in sf['permission'] and req_group in sf['permission']['groups'] ) or ( 'users' in sf['permission'] and req_user in sf['permission']['users'] ) ): perror(404,"Area access forbidden")

  #Check the area advanced run parameters
  tut_areamountmode='ro'
  if 'advanced' in ar:
    if 'runpath' in ar['advanced']:
      tut_areaname=ar['advanced']['runpath']
      tut_scenariopath=arg+os.sep+'index.json'
      tut_scenariopath=tut_scenariopath[len(tut_areaname)+1:]
    if 'mountmode' in ar['advanced']: tut_areamountmode=ar['advanced']['mountmode']

  #Create run command
  cmd=['/bin/bash','/opt/localcoda/backend/bin/backend_run.sh','-q','-d',tut_areaname,tut_scenariopath]
  if tut_areamountmode=="rw": cmd+=['-W']
  if req_user: cmd+=['-U',req_user]
  #Run command and get id as output
  r = subprocess.run(cmd, capture_output=True, text=True)
  if r.returncode != 0: perror(500,f"Cannot start tutorial. Tutorial run returned {r.returncode}. Error was {r.stderr.strip()}")

  #All ok. Id is returned
  psuccess({"uuid":r.stdout.strip()})
elif cmd=="ls":
  #List running scenarios

  #Sanitize the uuid (if specified)
  arg=''.join(c for c in arg if c in set("abcdefghijklmnopqrstuvwxyz0123456789-"))

  #Create run command
  cmd=['/bin/bash','/opt/localcoda/backend/bin/backend_ls.sh',arg]
  if req_user: cmd+=['-U',req_user]

  #Run command and get its output
  r = subprocess.run(cmd, capture_output=True, text=True)
  if r.returncode != 0: perror(500,f"Cannot list tutorials. Tutorial list returned {r.returncode}")
  psuccess(r.stdout.strip())

elif cmd=="stop":
  #Stop running scenario

  #Sanitize the uuid (if specified)
  arg=''.join(c for c in arg if c in set("abcdefghijklmnopqrstuvwxyz0123456789-"))

  #Check you are specifying an id
  if arg=="": perror(403,"Invalid ID")

  #First list the scenarios to check it is actually running
  cmd=['/bin/bash','/opt/localcoda/backend/bin/backend_ls.sh',arg]
  if req_user: cmd+=['-U',req_user]
  r = subprocess.run(cmd, capture_output=True, text=True)
  if r.returncode != 0: perror(500,f"Cannot list tutorials. Tutorial list returned {r.returncode}")

  #Parse the output (is json)
  try:
    l=json.loads(r.stdout.strip())
  except json.JSONDecodeError as e:
    perror(500,f"Cannot list tutorials. Invalid output")

  #Look if we find the item
  ar=next((i for i in l if i.get("id") == arg), None)
  if ar is None: perror(403,f"Id not running")

  #Stop it
  cmd=['/bin/bash','/opt/localcoda/backend/bin/backend_stop.sh',arg]
  if req_user: cmd+=['-U',req_user]
  r = subprocess.run(cmd, capture_output=True, text=True)
  if r.returncode != 0: perror(500,f"Cannot stop tutorial. Tutorial stop returned {r.returncode}")

  psuccess({"result":"ok"})

elif cmd=="me":
  #Get current user info and its configuration
  psuccess({"user":req_user,"group":req_group})

else:
  perror(400, "Invalid command")
