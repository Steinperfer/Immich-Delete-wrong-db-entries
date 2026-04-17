inside /immich-app  
sudo chmod +x DeleteImageFromDBbyERROR.sh  
./immich_cleanup.sh  
  
  
About:
Check Immich DB for wrong uploads, sometimes if you upload an imiage and it wont load or open on the website 
you need to delete the DB entry, my script checks for all errors and deletes the entrie, 
so you need to try to open every image that wont load while my script is running or after and running it agian
  
THIS WONT DELET IMAGES ONLY THE DB ENTRIE  
this will let you upload your personal images agian  
