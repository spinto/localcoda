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
def psuccess(data, c=200, nocache=True):
    """
    Send a successful JSON response in a CGI script.
    
    Parameters:
        data (dict|list|str|int|float|bool): The data to send as JSON.
        c (int, optional): HTTP status code (default 200).
    """
    # CGI scripts must print the headers first
    if nocache:
      # Disable caching by default
      print(f"Status: {c} {http_res.get(c, '')}\nContent-Type: application/json\nCache-Control: no-cache, no-store, must-revalidate\nPragma: no-cache\nExpires: 0\n")
    else:
      print(f"Status: {c} {http_res.get(c, '')}\nContent-Type: application/json\n")

    # Ensure the data is JSON-serializable
    if isinstance(data,str):
      print(data)
    else:
      print(json.dumps(data))
    sys.exit(0)
def get_user_info(level=0):
  def luf(_cache=None):
    if _cache is None:
      #Load users file (if present)
      try:
        cf=os.environ['TUTORIALS_VOLUME_ACCESS_MOUNT']+os.sep+'users.json'
        with open(cf,"r", encoding="utf-8") as f:
          _cache=json.load(f)
      except json.JSONDecodeError as e:
        perror(500,f"Invalid user file: {e}")
      except OSError as e:
        perror(500,f"Cannot read file. {e}")
    return _cache

  #Returns None if the user authentication is disabled (all users will be able to access)
  if 'X-USER' not in os.environ or os.environ['X-USER'] == '':
    return None
  usr=os.environ['X-USER']
  #Check if we need to impersonate an user
  if 'HTTP_COOKIE' in os.environ and '_localcoda_impersonate' in os.environ['HTTP_COOKIE']:
    impersonate_request=next((kv[1].strip() for kv in (p.split("=",1) for p in os.environ['HTTP_COOKIE'].replace("; ", ";").split(";")) if kv[0].strip()=="_localcoda_impersonate"), None)
    if impersonate_request is not None:
      #Check if we have the rights to impersonate
      uf=luf()
      if 'users' in uf and usr in uf['users'] and 'can_impersonate' in uf['users'][usr] and uf['users'][usr]['can_impersonate']=='true':
        #We impersonate the user
        usr=impersonate_request
  #Level 0, return if the user is authenticated, or None if not
  r={'username':usr}
  #Level 1, return also group names
  if level>0:
    grp=[]
    #Load users file (if present)
    uf=luf()
    if 'users' in uf and usr in uf['users'] and 'groups' in uf['users'][usr]:
      grp=uf['users'][usr]['groups']
    r['groups']=grp
  #Level 2, return also overrides
  if level>1:
    ovr={}
    for g in grp:
      if g in uf['groups'] and 'overrides' in uf['groups'][g]:
        for o in uf['groups'][g]['overrides']:
          ovr[o]=uf['groups'][g]['overrides'][o]
    r['overrides']=ovr
  #Return also if user can impersonate
  if level>2:
    if 'users' in uf and usr in uf['users'] and 'can_impersonate' in uf['users'][usr]:
      r['can_impersonate']=uf['users'][usr]['can_impersonate']
  #Return user
  return r

#Read URI
path_info=os.environ['PATH_INFO']
path_par=path_info[path_info.find('/ctl/')+5:].split('/',1)
cmd=path_par[0]
arg=path_par[1] if len(path_par)>1 else ''

#Execute command
if cmd=="browse":
  #Load user info (if any). We need only the user and the groups, so level 1. user_groups will be None if authentication is disabled, otherwise it is the list of groups which we need to match with the structure group metadata
  user_info=get_user_info(1)
  user_groups=None if user_info is None else user_info['groups']

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
    if user_groups is not None and 'group' in st_prev and st_prev['group'] not in user_groups: perror(403,f"Access forbidden to {cur_path}")

    #Load a structure.json file, if present
    structfile=tut_basepath+cur_path+os.sep+"structure.json"
    if os.path.isfile(structfile):
      try:
        with open(structfile,"r", encoding="utf-8") as f:
          st=json.load(f)
      except json.JSONDecodeError as e:
        perror(500,f"Invalid structure: {e}")
      except OSError as e:
        perror(500,f"Cannot read file. {e}")
    else:
      st={}
    
    #Check permissions in the current structure file (if present)
    if user_groups is not None and 'group' in st and st['group'] not in user_groups: perror(403,f"Access forbidden to {cur_path}")

    #Add title and description, if not present, use the previous, if not present, use the path as title
    if 'title' not in st:
      if 'title' in st_prev:
        st['title']=st_prev['title']
      else:
        st['title']=el.replace('-',' ').title()
    if 'description' not in st and 'description' in st_prev: st['description']=st_prev['description']
    #Add the path to the path list
    st_path+=[{'title':st['title'],'path':cur_path}]

  #Add the path list to the structure, remove what we do not need from it
  st['paths']=st_path
  if 'group' in st: del st['group']

  #If you do not have a list of items in the structure, add it by scanning the directory for sub-directories
  if 'items' not in st:
    #Get the list of directories (sorted)
    subdirs = sorted(next(os.walk(tut_abspath))[1])
    st['items'] = [{"path": d} for d in subdirs]
    del subdirs

  #Load scenarios titles and descriptions (if not overwritten)
  new_items=[]
  for d in st['items']:
    #Delete items not needed
    if 'advanced' in d: del d['advanced']
    #Check permissions if set and delete items who do not meet them
    if 'group' in d:
      if user_groups is not None and d['group'] not in user_groups:
        continue
      else:
        del d['group']
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
      if 'title' not in d and 'title' in fv: d['title']=fv['title']
      if 'description' not in d and 'description' in fv: d['description']=fv['description']
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
      if 'title' not in d and 'title' in fv: d['title']=fv['title']
      if 'description' not in d and 'description' in fv: d['description']=fv['description']
      if 'items' in fv: d['items_count']=len(fv['items'])
    #If we have just sub-directories inside, still this is a structure
    else:
      #Check if we have subdirectories inside
      d['type']='structure';
      d['items_count']=len(next(os.walk(tut_abspath+d['path']))[1])
      #If the sub-directory is empty, then do not show it
      if d['items_count']==0: continue
    #If still title and description is not set, set it to the name of the folder and to an empty string
    if 'title' not in d: d['title']=d['path'].replace('-',' ').title()
    if 'description' not in d: d['description']=''
    new_items.append(d)
  st['items']=new_items

  #Display the output (and enable caching, as this can be cached)
  psuccess(st,200,False)

elif cmd=="run":
  #Load user info (if any). We need the user, the groups and the overrides, so level 2. user_groups will be None if authentication is disabled, otherwise it is the list of groups which we need to match with the structure group metadata
  user_info=get_user_info(2)
  user_groups=None if user_info is None else user_info['groups']
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
    if user_groups is not None and 'group' in st_prev and st_prev['group'] not in user_groups: perror(403,f"Access forbidden to {cur_path}")

    #Load a structure.json file, if present
    structfile=tut_basepath+cur_path+os.sep+"structure.json"
    if os.path.isfile(structfile):
      try:
        with open(structfile,"r", encoding="utf-8") as f:
          st=json.load(f)
      except json.JSONDecodeError as e:
        perror(500,f"Invalid structure: {e}")
      except OSError as e:
        perror(500,f"Cannot read file. {e}")
    else:
      st={}

    #Check permissions in the current structure file (if present)
    if user_groups is not None and 'group' in st and st['group'] not in user_groups: perror(403,f"Access forbidden to {cur_path}")

  #Load scenario to check if it is valid
  try:
    with open(tut_abspath+"index.json","r", encoding="utf-8") as f:
      sf=json.load(f)
  except json.JSONDecodeError as e:
    perror(500,f"Invalid scenario file: {e}")
  except OSError as e:
    perror(500,f"Cannot read file. {e}")

  #Check you have permissions to run the scenario also (not all the paths)
  if user_groups is not None and 'group' in sf and sf['group'] not in user_groups: perror(403,f"Access forbidden!")

  #Extract area name and scenario path
  if 'advanced' in ar and 'runpath' in ar['advanced']:
    #Advanced parameters rewrite area name
    tut_areaname=ar['advanced']['runpath']
  else:
    tut_areaname=tut_splitpath[1]
  tut_scenariopath=arg+os.sep+'index.json'
  tut_scenariopath=tut_scenariopath[len(tut_areaname)+1:].lstrip('/')

  #Create run command
  cmd=['/bin/bash','/opt/localcoda/backend/bin/backend_run.sh','-o','TUTORIALS_VOLUME_ACCESS_MOUNT=/data/tutorials','-q','-d',tut_areaname,tut_scenariopath]
  if user_groups is not None:
    #If user is authenticated, add username
    cmd+=['-U',user_info['username']]
    #And add overrides
    ov=user_info['overrides']
    for o in ov:
      cmd+=['-o',f'{o}={ov[o]}']
  #Run command and get id as output
  r = subprocess.run(cmd, capture_output=True, text=True)
  if r.returncode == 42: perror(429,f"Cannot start tutorial. Tutorial run returned {r.returncode}. Error was {r.stderr.strip()}.")
  if r.returncode != 0: perror(500,f"Cannot start tutorial. Tutorial run returned {r.returncode}. Error was {r.stderr.strip()}")

  #All ok. Id is returned
  psuccess({"uuid":r.stdout.strip()})
elif cmd=="ls":
  #List running scenarios

  #Sanitize the uuid (if specified)
  arg=''.join(c for c in arg if c in set("abcdefghijklmnopqrstuvwxyz0123456789-"))

  #Create run command
  cmd=['/bin/bash','/opt/localcoda/backend/bin/backend_ls.sh',arg]

  #Add user info (only username, level 0)
  user_info=get_user_info(0)
  if user_info is not None: cmd+=['-U',user_info['username']]

  #Run command and get its output
  r = subprocess.run(cmd, capture_output=True, text=True)
  if r.returncode != 0: perror(500,f"Cannot list tutorials. Tutorial list returned {r.returncode}")
  psuccess(r.stdout.strip())

elif cmd=="stop":
  #Stop running scenario

  #Sanitize the uuid (if specified)
  arg=''.join(c for c in arg if c in set("abcdefghijklmnopqrstuvwxyz0123456789-"))

  #Check you are specifying an id
  if arg=="": perror(400,"Invalid ID")

  #First list the scenarios to check it is actually running
  cmd=['/bin/bash','/opt/localcoda/backend/bin/backend_ls.sh',arg]
  
  #Add user info (only username, level 0)
  user_info=get_user_info(0)
  if user_info is not None: cmd+=['-U',user_info['username']]

  #Run command and get its output
  r = subprocess.run(cmd, capture_output=True, text=True)
  if r.returncode != 0: perror(500,f"Cannot list tutorials. Tutorial list returned {r.returncode}")

  #Parse the output (is json)
  try:
    l=json.loads(r.stdout.strip())
  except json.JSONDecodeError as e:
    perror(500,f"Cannot list tutorials. Invalid output")

  #Look if we find the item
  ar=next((i for i in l if i.get("id") == arg), None)
  if ar is None: perror(400,f"Id not running")

  #Stop it
  cmd=['/bin/bash','/opt/localcoda/backend/bin/backend_stop.sh',arg]
  
  #Add user info (only username, level 0)
  user_info=get_user_info(0)
  if user_info is not None: cmd+=['-U',user_info['username']]

  #Run command and get its output
  r = subprocess.run(cmd, capture_output=True, text=True)
  if r.returncode != 0: perror(500,f"Cannot stop tutorial. Tutorial stop returned {r.returncode}")

  psuccess({"result":"ok"})

elif cmd=="me":
  #Get config file constrains
  try:
    with open('/opt/localcoda/backend/cfg/conf','r') as f:
      v={}
      for l in f:
        if l.startswith('MAXIMUM_RUN_PER_USER'):
          v['MAXIMUM_RUN_PER_USER']=l.split('=',1)[1].strip().split(' ',1)[0].split('#',1)[0]
        elif l.startswith('TUTORIAL_MAX_TIME'):
          v['TUTORIAL_MAX_TIME']=l.split('=',1)[1].strip().split(' ',1)[0].split('#',1)[0]
        elif l.startswith('TUTORIAL_EXIT_ON_DISCONNECT'):
          v['TUTORIAL_EXIT_ON_DISCONNECT']=l.split('=',1)[1].strip().split(' ',1)[0].split('#',1)[0]
        if(len(v)==3): break
  except FileNotFoundError:
    perror(500,f"Cannot access backend configuration. Please contact administrator")
  except IOError as e:
    perror(500,f"IO error while accessing backend configuration. Please contact administrator")

  #Get full user info
  user_info=get_user_info(99)
  if user_info:
    #Add what is not an override
    if 'overrides' in user_info:
      for k in v:
        if k not in user_info['overrides']:
          user_info['overrides'][k]=v[k]
    #Check if you are impersonating someone
    if 'HTTP_COOKIE' in os.environ and '_localcoda_impersonate' in os.environ['HTTP_COOKIE']:
      user_info['impersonatedby']=os.environ['X-USER'] if 'X-USER' in os.environ else ""
    #Print the user info
    psuccess(user_info)
  else:
    psuccess({"username":""})
elif cmd=="impersonate":
  #Check if user can impersonate
  user_info=get_user_info(3)
  if 'can_impersonate' not in user_info or user_info['can_impersonate']!='true': perror(403,"User has no rights to impersonate")
  if 'QUERY_STRING' not in os.environ or os.environ['QUERY_STRING'] is None: perror(400,"bad request")
  usr_value = next((p.split("=",1)[1] for p in os.environ['QUERY_STRING'].split("&") if p.startswith("usr=")), None)
  if usr_value is None: perror(400,"bad request")
  urldecode = lambda s: "".join(chr(int(s[i+1:i+3],16)) if s[i]=="%" else (" " if s[i]=="+" else s[i]) for i in range(len(s)) if s[i]!="%" or i+2<len(s))
  usr_value_dec = urldecode(usr_value)
  print(f"Set-Cookie: _localcoda_impersonate={usr_value_dec};")
  print("Location: /")
  perror(302,"done")

elif cmd=="unimpersonate":
  #Clear cookie
  print("Set-Cookie: _localcoda_impersonate=; Expires=Thu, 01 Jan 1970 00:00:00 GMT;")
  print("Location: /")
  perror(302,"done")
  
else:
  perror(400, "Invalid command")
