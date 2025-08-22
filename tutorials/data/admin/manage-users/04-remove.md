To remove any override or group assignment, you can use the "unset" command, for example

```
users-mgr unset group testgroup TUTORIAL_MAX_TIME
users-mgr unset user testuser group=testgroup
```{{exec}}


To remove all authorization for an user, you can run

```
users-mgr del user testuser
```{{exec}}

And to remove a group you can run

```
users-mgr del group testgroup
```{{exec}}
