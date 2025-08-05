<script lang="ts">
import { writable, get, type Writable, type Readable } from 'svelte/store';
  import SidebarContainer from './sidbarConatiner.svelte';
    import { getContext } from 'svelte';
    import { ProfileSession } from './profile';
  let { close, updateNick, isOpen, displayStore }: {updateNick: (nick: string) => void,close:() => void, isOpen: boolean, displayStore: Readable<string>} = $props();

  let display: string = $state('');

  function closeHandler() {
    display = get<string>(displayStore); // reset display to the current store value
    close();
  }
  displayStore.subscribe(value => {
    display = value;
  });

  let profile = getContext('profile') as ProfileSession;
</script>
<SidebarContainer
  isOpen={isOpen}
  close={closeHandler}
>
<div class="flex items-center justify-between p-6 border-b border-gray-200 bg-gradient-to-r from-blue-600 to-purple-600 text-white" >
  <h2 class="text-2xl font-bold">Profile</h2>
  <button 
    onclick={closeHandler}
    class="text-white hover:text-gray-200 transition-colors duration-200"
    aria-label="Close high scores"
  >
    <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
    </svg>
  </button>
</div>
  <div class="p-2">
    <div class="mb-6">
        <label for="default-input" class="block mb-2 font-medium text-gray-900">Display Name</label>
        <div class="flex">
          <input type="text" bind:value={display} class="bg-gray-50 border border-gray-300 text-gray-900 text-sm focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5">
          <button class="px-2 py-2 font-medium transition-all duration-200 bg-blue-500 text-white" onclick={() => {
            updateNick(display);
          }} >
            <div class="flex items-center space-x-2">
              <svg xmlns="http://www.w3.org/2000/svg" width="30" height="30" fill="currentColor" class="bi bi-check-lg" viewBox="0 0 16 16">
                <path d="M12.736 3.97a.733.733 0 0 1 1.047 0c.286.289.29.756.01 1.05L7.88 12.01a.733.733 0 0 1-1.065.02L3.217 8.384a.757.757 0 0 1 0-1.06.733.733 0 0 1 1.047 0l3.052 3.093 5.4-6.425z"/>
              </svg>
            </div>
          </button>
        </div>
    </div>

  </div>

</SidebarContainer>

