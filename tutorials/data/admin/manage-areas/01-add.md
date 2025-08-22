Your areas are located in the main space of the tutorial folder `/etc/localcoda/tutorial`. You can list them via

```
ls -l
```{{exec}}

Areas are just sub-folders in the main folder.

To add a new area, you need just to create a new folder and edit the `structure.json`{{}} file `items`{{}} field with the path to such folder. There is a wrapper script to do so more safely, as an invalid `structure.json`{{}} file will cause localcoda to misbehave.

```
area-mgr add test-area
```{{exec}}

Now your new area should be configured. You should see it now from [the Areas page]({{TRAFFIC_MAINAPP}}/#browse)
