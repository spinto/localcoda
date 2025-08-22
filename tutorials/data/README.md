This is the main tutorial volume for localcoda.

You can create "areas" as sub-directories of this volume. Inside these areas there can be nested tutorials or scenarios, controlled via the "structure.json" (for tutorials) and "index.json" (for scenarios). When running a scenario via the frontend, the entire area will be mounted in the scenario (in read-only).

You can create a "areas.json" file within this volume to control the visibility of the tutorials/workspace/scenarios in the frontend, using their "visibility attribute", and overwrite their "title" or "description" attributes.

The "admin" area in this volume is a special area, and hosts tutorial who can have "superuser" access to the system. You should not edit it unless you know what you are doing.

For more information about how to add/remove/delete areas/tutorials/scenarios and manage their attributes run the "volume-manager" tutorial in the admin area.
