A localcoda scenario is composed by a folder containing an `index.json`{{}} file, and several other files with the details of the scenario. Localcoda is compatible with [Killercoda](https://killercoda.com/creators) scenario format, and can support most of its features (like foreground scripts, background scripts, assets, etc...). You can get more information and examples about creating an scenario file from the [Killercoda creators](https://killercoda.com/creators) page.

Once you have a scenario, you need to place it in one of your area folder. You can list your area folders via

```
ls -l
```{{exec}}

To add a new tutorial/scenario, you need just to add a new sub-folder. For example

```
mkdir -p scenario-examples
cd scenario-examples
```{{exec}}

Now you need to fill your directory with your tutorials/scenario files (the `index.json`{{}} and its related files). A quick way to do that is to get them from a git repository. Avoid anyway to use `git clone`{{}} here, as you will then put in your tutorial folder all the internal git repository files (which may lead to unwanted leaks and more space used).

To download just the fails from the main branch of a git repository you can run

```
curl -L https://github.com/killercoda/scenario-examples/tarball/main | tar zxv --strip-components=1
```{{exec}}

Now, you you go back to your area page, you should see the new scenario-examples folder with your scenarios example, you can pick one and start it.
