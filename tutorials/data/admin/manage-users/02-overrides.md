Groups allow you also to control "overrides", which are specific user configuration parameters for the execution of the scenarios, which override the default ones co ntained in the `backend/cfg/conf` file of your localcoda deployment. Allowed "override" parameters are:
- ***TUTORIAL_MAX_TIME***: sets the maximum time, in seconds, a scenario can run. After this time expires, the scenario is automatically terminated. If set to -1, the scenario is never terminated and needs to be manually shutdown.
- ***TUTORIAL_EXIT_ON_DISCONNECT***: if set to true, will cause scenario to be terminated after the user closes the scenario page in the browser
- ***MAXIMUM_RUN_PER_USER***: sets the maximum number of parallel scenario instances a user can run. If set to -1, the user can run unlimited instances

The overrides are assigned to groups, which are then assigned to users. So, if you want your users in the "testgroup" to be able to run tutorials only for upt 5 minutes and only one tutorial at the time, you can run

```
users-mgr set group testgroup TUTORIAL_MAX_TIME=300 MAXIMUM_RUN_PER_USER=1
```

