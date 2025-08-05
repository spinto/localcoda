You tutorials are located in the tutorials folder. You can list them via

```
cd ~/tutorials
ls -l
```{{exec}}

To add a new tutorial, you need just to add a new folder. An easy way is to download them from a remote git repository. Note that it is not suggested to use `git clone`{{}} here, as you will then put in your tutorial folder all the internal git repository files (which may lead to unwanted leaks and more space used)

```
curl -L https://github.com/killercoda/scenario-examples/tarball/main | tar zx --transform 's|^\(.*\)-[^/]*|\1|'
```{{exec}}

You can also use `structure.json`{{}} file to edit the order and visibility of the tutorials.
