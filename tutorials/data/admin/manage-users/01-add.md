The users authorization parameters are located in the main space of the tutorial folder `/etc/localcoda/tutorial`{{}}, in the `users.json`{{}} file.

Note that these are only authorization parameters. Authentication is done with an external Identity Provider and configured upon localcoda deployment. The Authentication username given by the enternal Identity Provider is then used by localcoda for authentication, as mapped by the `users.json`{{}} file.

Changing directly the `users.json`{{}} file should be avoided, as an invalid `users.json`{{}} will cause localcoda to misbehave. A wrapper script to operate with the `users.json`{{}} file is provided. For example, to list users, you can run

```
user-mgr ls user
```{{exec}}

To add a new user, for example the pippo user, you can then run

```
user-mgr add user testuser
```{{exec}}

Note that again thsi is only authorization for that user. The user needs to also be registered with that username into the external Identity Provider configurred in your localcoda deployment.

Once a user authorization entry is created, this user will be not mapped to any group. To manage authorization, localcoda users groups who are then referenced by the areas and scenarios "group" metadata.

To list existing groups you can run

```
user-mgr ls group
```{{exec}}

To create a new group for the user pippo, named "testgroup", you can run

```
user-mgr add group testgroup
```

And now you can allocate the pippo user to this group

```
user-mgr set user testuser group=testgroup
```{{exec}}

Now the user list will show you the user is assigned to the given group

```
user-mgr ls user testuser
```{{exec}}

and the user will be able to access all areas, tutorials and scenario who have the "group" metadata set to "testgroup".
