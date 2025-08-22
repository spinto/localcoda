When you have authentication enabled, for debug or control purposes, you may want to impersonate another user.

To do so, you need first to ensure your user has the "can_impesonate" flab set. For example, if your user is named "admin" you can run

```
user-mgr set user admin can_impersonate=true
```

Once this is done, in the [the User page]({{TRAFFIC_MAINAPP}}/#user) you will see a button allowing you to impersonate any user, given its username.
