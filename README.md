```
sudo chmod +x DeleteImageFromDBbyERROR.sh  
./DeleteImageFromDBbyERROR.sh  
```
  
# About:
Check Immich DB for wrong uploads, sometimes if you upload an imiage and it wont load or open on the website 
you need to delete the DB entry, my script checks for all errors and deletes the entrie, 
so you need to try to open every image that wont load while my minimal script is running or after and running it agian
# Update:
FixImmichDB now also deletes the image from your disk if it has no entry in the db, 
this can hapen if you import libarys and then remove them, no image will get deletet only the db entry

