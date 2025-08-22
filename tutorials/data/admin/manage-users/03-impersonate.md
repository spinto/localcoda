When you have authentication enabled, for debug or control purposes, you may want to impersonate another user.

To do so, you need first to ensure your user has the "can_impesonate" flag set. For example, if your user is named "admin" you can run

```
user-mgr set user admin can_impersonate=true
```{{exec}}

Once this is done, in the [the User page]({{TRAFFIC_MAINAPP}}/#user) you will see a button allowing you to impersonate any user, given its username.

If you impersonate the `testuser` you just created, you will see that in [its User page]({{TRAFFIC_MAINAPP}}/#user) the `TUTORIAL_MAX_TIME` is set to 300, instead of the default value for the main user. This because the "testuser" is a member of the "testgroup" which has this value as configured override. Also, you you try to start a scenario as `testuser`, you will see its maximum time is 5 minutes, and it will be deleted after that time passes.
