Your new area is now quite bare, you can extend it by setting one of the following parameters

- ***title***: The title of the area in the areas page.
- ***description***: The description of the area in the areas page.
- ***img***: A URI linking an image to diplay in the area tile. This URI need to point to an external resource or be a data URI, as serving of images contained in the area folders is not supported.
- ***theme***: Color of the tile, allowed themes are 'red, blue, green, yellow, orange, purple, pink, grey, navy, brown, black, white' with additional potential '-light' and '-dark' suffixes.
- ***group***: If authentication is enabled, this area will be accessible only from people in this group. If group is not set or empty, then all users can access it

To set a area parameter you need to edit the `structure.json`{{}} file `items`{{}} field corresponding to the area. There is a wrapper script to do so more safely, as an invalid `structure.json`{{}} file will cause localcoda to misbehave.

```
area-mgr set test-area title="New test area" description="This is just for test" theme=orange-dark
```{{exec}}

Now your you should see the updated area from [the Areas page]({{TRAFFIC_MAINAPP}}/#browse)

If you want to remove some parameter, for example restore the default there, you can run

```
area-mgr unset test-area theme
```{{exec}}

At this point you should add scenarios to this area. There is a tutorial for this in the "admin" area, which is accessible for the administrators. If you want to allow users who can access only the new area you created to be able to create scnearios there you can copy the manage-scenario folder inside the new area via

```
cp -r admin/manage-scenarios test-area/
```{{exec}}

and potentially edit its "group" parameter in the `test-area/manage-scenario/index.json`{{}} file so that it can be accessed by the developers of the new area (and only by them)

As a final note, if you see the `structure.json`{{}} file default contents, there is also a set of "advanced" parameter you can configure for the areas. These are parameter specific to administration areas who allow more "power" to the scenarios inside that area and thus you should just ignore them (or set them very carefully)

