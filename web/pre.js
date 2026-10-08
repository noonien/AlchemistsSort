// Set up before the game's main() runs: where its data is, and a save folder
// kept in the browser's IndexedDB, loaded before the game reads it and
// written back whenever a file in it changes.
Module.preRun = Module.preRun || [];
Module.preRun.push(() => {
  ENV.ALCHEMIST_SORT_DATA = '/data';
  ENV.XDG_DATA_HOME = '/save';
  FS.mkdir('/save');
  FS.mount(IDBFS, { autoPersist: true }, '/save');
  addRunDependency('saves');
  FS.syncfs(true, (err) => {
    if (err) console.warn('Could not load saved progress:', err);
    removeRunDependency('saves');
  });
});
