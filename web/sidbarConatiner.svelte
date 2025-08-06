<script lang="ts">
  import { clickOutside } from './clickOutside';
  let { close, isOpen, children}: {close:() => void, isOpen: boolean, children: any} = $props();
</script>
<div 
    class="fixed top-0 right-0 h-full w-96 md:w-200 bg-white shadow-2xl transform transition-transform duration-300 ease-in-out z-50 {isOpen ? 'translate-x-0' : 'translate-x-full'} flex flex-col"
  use:clickOutside onClickOutside={() => {
    if (isOpen) close(); 
  }}
>
  {@render children()}
</div>


<style>
  /* Custom scrollbar for the content area */
  :global(.overflow-y-auto::-webkit-scrollbar) {
    width: 6px;
  }
  
  :global(.overflow-y-auto::-webkit-scrollbar-track) {
    background: #f1f5f9;
  }
  
  :global(.overflow-y-auto::-webkit-scrollbar-thumb) {
    background: #cbd5e1;
    border-radius: 3px;
  }
  
  :global(.overflow-y-auto::-webkit-scrollbar-thumb:hover) {
    background: #94a3b8;
  }
</style>



