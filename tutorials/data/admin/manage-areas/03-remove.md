To remove a an area, you need first to cleanup all its contents. For example

```
rm -rf test-area/*
```{{exec}}

And then you need to remove the area directory and remove it from the `structure.json`{{}} file. There is a wrapper script to do so more safely, as an invalid `structure.json`{{}} file will cause localcoda to misbehave.

```
area-mgr del test-area
```{{exec}}
