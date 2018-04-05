function New-ManifestModule
{
	<#
	.SYNOPSIS
		New-ManifestModule is a function for creating Manifest Modules out of a folder of PS1 files.
	.DESCRIPTION
		New-ManifestModule takes a directory of one or more PS1 files and turns it into a Manifest
		Module. Using the 'CompilePS1Files' parameter you can either keep multiple PS1 files split up and
		nested inside the new Manifest Module or combine them and place them into a PSM1.
	.EXAMPLE
		PS> New-ManifestModule -Path "C:\Temp\MyNewModule"
		
		This example takes the PS1 files within the directory C:\Temp\MyNewModule and creates a Manifest Module
		called 'MyNewModule' in the temporary folder C:\Temp\MyNewModule\MyNewModule. The PS1 files are left alone
		and added to the NestedModules property of the Manifest.
	.EXAMPLE
		PS> New-ManifestModule -Path "C:\Temp\MyNewModule" -PublishLocation "\\server\share"
	
		This example takes the PS1 files within the directory C:\Temp\MynewModule and creates a Manifest Module
		called 'MyNewModule' in the temporary folder C:\Temp\MyNewModule\MyNewModule. The PS1 files are left alone
		and added to the NestedModules property of the Manifest. It then copies the Manifest Module folder
		to \\server\share.
	.EXAMPLE
		PS> New-ManifestModule -Path "C:\Temp\MyNewModule" -CustomProperties @{'Author' = 'Cody Douglas';'CompanyName' = 'intrntpirate.com'}
	
		This example takes the PS1 files within the directory C:\Temp\MyNewModule and creates a Manifest Module
		called 'MyNewModule' in the temporary folder C:\Temp\MyNewModule\MyNewModule. The PS1 files are left alone
		and added to the NestedModules property of the Manifest. The 'Author' and 'CompanyName' properties in the
		Manifest are also set to 'Cody Douglas' and 'intrntpirate.com'.
	.EXAMPLE
		PS> New-ManifestModule -Path "C:\Temp\MyNewModule" -CompilePS1Files $true
	
		This example takes the PS1 files within the directory C:\Temp\MyNewModule and creates a Manifest Module
		called 'MyNewModule' in the temporary folder C:\Temp\MyNewModule\MyNewModule. The PS1 files are merged into a
		PSM1 file located at C:\Temp\MyNewModule\MyNewModule\MyNewModule.psm1. The Manifest RootModule parameter
		is then updated to point to the PSM1.
	.EXAMPLE
		PS> New-ManifestModule -Path "C:\Temp\MyNewModule" -DigitallySign $true
	
		This example takes the PS1 files within the directory C:\Temp\MyNewModule and creates a Manifest Module
		called 'MyNewModule' in the temporary folder C:\Temp\MyNewModule\MyNewModule. The PS1 files are left alone
		and added to the NestedModules property of the Manifest. The Manifest and any PSM1 or PS1 files within the
		temporary folder are then digitally signed with either the only Code Signing certificate in the current users
		personal certificate store, or the selected Code Signing certificate.
	#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateScript({
				If (-not (Test-Path -Path $_))
				{
					throw "The path [$_] does not exist. Try again."
				}
				else
				{
					If ($_ -like "*/*")
					{
						throw "You cannot use forward slashes."
					}
					Else
					{
						$Split = $_.Split("\")
						If ($Split[$Split.Count - 1] -like "*.*")
						{
							throw "You must specify a directory, not a file."
						}
						Else
						{
							$true
						}	
					}
				}
			})]
		#Enter the path of a folder that contains the PS1 files that you want converted into a Manifest Module.
		[string]$Path,
		[ValidateScript({
				If ($_ -eq (Get-Item -Path $Path).Directoryname)
				{
					throw "You cannot publish the module to its current directory. Try again."
				}
				else
				{
					If ($_ -like "*/*")
					{
						throw "You cannot use forward slashes."	
					}
					Else
					{
						$Split = $_.Split("\")
						If ($Split[$Split.Count - 1] -like "*.*")
						{
							throw "You must specify a directory, not a file."
						}
						Else
						{
							$true		
						}	
					}
				}
			})]
		#Enter the path of where the Manifest Module should be copied to after being created in a temporary folder within the Path location.
		[string]$PublishLocation,
		#Provide a hash table containing values for the Manifest file.
		[hashtable]$CustomProperties,
		#Select whether or not to merge PS1 files into a PSM1.
		[bool]$CompilePS1Files = $false,
		[ValidateSet('Prefix', 'Append')]
		#Select whether to pre-fix an existing PSM1 with PS1 files, or append an existing PSM1 with PS1 files.
		[string]$CompileTo = "Append",
		#Select whether or not to digitally sign the resulting Manifest Module.
		[bool]$DigitallySign = $false,
		#Specify the thumbprint of a code signing certificate to use.
		[string]$CertificateThumbprint,
		#Specify the URL of a time stamp service to use while digitally signing the Manifest Module.
		[string]$TimeStampURL,
		[switch]$Confirm,
		[switch]$WhatIf
	)
	If ($WhatIf.IsPresent)
	{
		$WhatIfPreference = $true
	}
	function Helper-GenerateArrayString
	{
		param (
			$arrayObject
		)
		$arrayString = "@("
		foreach ($Object in $arrayObject)
		{
			$arrayString = $arrayString + "'$Object',"
		}
		$arrayString = $arrayString.TrimEnd(',')
		$arrayString = $arrayString + ")"
		return, $arrayString
	}
	function Helper-Set-AuthenticodeSignature
	{
		param (
			$FilePath,
			$Certificate
		)
		Write-Verbose -Message "Beginning Helper-Set-AuthenticodeSignature."
		Write-Verbose -Message "Path: $FilePath"
		Write-Verbose -Message "Certificate: $($Certificate.Thumbprint)"
		Try
		{
			If ($WhatIfPreference -ne $true)
			{
				If (($TimeStampURL))
				{
					Set-AuthenticodeSignature -FilePath $FilePath -Certificate $Certificate -TimestampServer $TimeStampURL | Out-Null
				}
				Else
				{
					Set-AuthenticodeSignature -FilePath $FilePath -Certificate $Certificate | Out-Null
				}
			}
			Else
			{
				If (($TimeStampURL))
				{
					Write-Output "What if: Performing the operation `"Set-AuthenticodeSignature -FilePath $FilePath -Certificate $($Certificate.Thumbprint)`" -TimestampServer $TimeStampURL"
				}
				Else
				{
					Write-Output "What if: Performing the operation `"Set-AuthenticodeSignature -FilePath $FilePath -Certificate $($Certificate.Thumbprint)`""
				}
			}
		}
		Catch
		{
			Write-Error -Exception (@{ Source = "$($PSCmdlet.MyInvocation.MyCommand.Name)" }) -Message "An error occured while attempting to sign a file."
		}
	}
	function Helper-ShouldProcess
	{
		param (
			[string]$type = "YesNo",
			[string]$title = "Confirm",
			[string]$prompt
		)
		If ($Confirm.IsPresent)
		{
			return, $true
		}
		Else
		{
			If ($type -eq "YesNo")
			{
				$Yes = New-Object System.Management.Automation.Host.ChoiceDescription '&Yes'
				$No = New-Object System.Management.Automation.Host.ChoiceDescription '&No'
				$options = [System.Management.Automation.Host.ChoiceDescription[]] ($Yes, $No)
				switch (($Host.UI.PromptForChoice($title, $prompt, $options, 0)))
				{
					0 { return, $true }
					1 { return, $false }
				}
			}
		}
	}
	Write-Verbose -Message "Beginning $($PSCmdlet.MyInvocation.MyCommand.Name)..."
	Write-Verbose -Message "Path: $Path"
	If (($PublishLocation))
	{
		Write-Verbose -Message "PublishLocation: $PublishLocation"
	}
	If (($CustomProperties))
	{
		Write-Verbose -Message "CustomProperties: $true"
	}
	Else
	{
		Write-Verbose -Message "CustomProperties: $false"
	}
	Write-Verbose -Message "CompilePS1Files: $CompilePS1Files"
	Write-Verbose -Message "DigitallySign: $DigitallySign"
	If (($CertificateThumbprint))
	{
		Write-Verbose -Message "CertificateThumbprint: $CertificateThumbprint"
	}
	If (($TimeStampURL))
	{
		Write-Verbose -Message "TimeStampURL: $TimeStampURL"
	}
	$ManifestPropertyTypes = @{
		'NestedModules'			    = 'array';
		'RequiredModules'		    = 'array';
		'PrivateData'			    = 'hashtable';
		'TypesToProcess'		    = 'array';
		'FormatsToProcess'		    = 'array';
		'ScriptsToProces'		    = 'array';
		'RequiredAssemblies'	    = 'array';
		'FileList'				    = 'array';
		'ModuleList'			    = 'array';
		'FunctionsToExport'		    = 'array';
		'AliasesToExport'		    = 'array';
		'VariablesToExport'		    = 'array';
		'CmdletsToExport'		    = 'array';
		'DscResourcesToExport'	    = 'array';
		'CompatiblePSEditions'	    = 'array';
		'Tags'					    = 'array';
	}
	If (($Path.EndsWith("/")) -or ($Path.EndsWith("\")))
	{
		Write-Verbose -Message "Removing trailing backslash from supplied path..."
		$Path = $Path.TrimEnd('\', '/')
	}
	If (($PublishLocation.EndsWith("/")) -or ($PublishLocation.EndsWith("\")))
	{
		Write-Verbose -Message "Removing trailing backslash from supplied publish location..."
		$PublishLocation = $PublishLocation.TrimEnd('\', '/')
	}
	$Basename = (Get-Item -Path $Path).BaseName
	If ((Test-Path -Path "$Path\$Basename.psd1"))
	{
		Write-Verbose -Message "Importing existing manifest..."
		Try
		{
			$ManifestData = Invoke-Expression (Get-Content -Path $Path | Out-String)
		}
		Catch
		{
			Write-Error -Exception (@{ Source = "$($PSCmdlet.MyInvocation.MyCommand.Name)" }) -Message "An error occured while attempting to obtain the Manifest data."
		}
	}
	Else
	{
		Write-Verbose -Message "Creating empty manifest hash..."
		$ManifestData = @{ }
	}
	If ((Test-Path -Path "$Path\$Basename.psm1"))
	{
		Write-Verbose -Message "Importing existing PSM1..."
		$PSM12Export = @()
		$PSM12Export += (Get-Content -Path "$Path\$Basename.psm1")
	}
	If (($DigitallySign -eq $true))
	{
		Write-Verbose -Message "DigitallySign is enabled."
		If (($CertificateThumbprint))
		{
			Write-Verbose -Message "A certificate thumbprint was supplied. Locating certificate..."
			If ((Test-Path -Path "Cert:\CurrentUser\My\$CertificateThumbprint"))
			{
				Write-Verbose -Message "Certificate located."
				$Certificate = Get-ChildItem -Path "Cert:\CurrentUser\My\$CertificateThumbprint"
			}
			Else
			{
				Write-Error -Exception (@{ Source = "$($PSCmdlet.MyInvocation.MyCommand.Name)" }) -Message "Unable to locate the supplied certificate thumbprint."
			}
		}
		Else
		{
			Write-Verbose -Message "No certificate thumbprint was supplied. Attempting to locate a Code Signing certificate in the current user store..."
			$Certificates = Get-ChildItem -Path "Cert:\CurrentUser\My\" | Where-Object { $_.EnhancedKeyUsageList.ObjectId -eq "1.3.6.1.5.5.7.3.3" }
			If ($Certificates.count -ge 2)
			{
				$Certificate = $Certificates | Out-GridView -Title "Select a Certificate" -OutputMode Single
			}
			elseif (($Certificates))
			{
				Write-Verbose -Message "Located Code Signing certificate $($Certificates.Thumbprint)."
				$Certificate = $Certificates
			}
			else
			{
				Write-Error -Exception (@{ Source = "$($PSCmdlet.MyInvocation.MyCommand.Name)" }) -Message "No Code Signing certificates available."
			}
		}
	}
	$Process = $false
	If (($PublishLocation))
	{
		If (($PublishLocation.Split('\')[$_.count -1]) -eq $Basename)
		{
			Write-Verbose -Message "The publish location specified is the same name as the basename. Reconfiguring the publish location to be the next directory up..."
			$PublishLocation = ($PublishLocation.Split('\')[0 .. ($_.count - 2)]) -join '\'
			Write-Verbose -Message "New publish location: $PublishLocation"
		}
	}
	Write-Verbose -Message "Evaluating publish location and temporary folders..."
	If ($WhatIfPreference -ne $true)
	{
		If ((Test-Path -Path "$PublishLocation\$Basename"))
		{
			Write-Verbose -Message "Publish location already exists."
			If ((Helper-ShouldProcess -type "YesNo" -prompt "Overwrite the existing published module $PublishLocation\$Basename") -eq $true)
			{
				Try
				{
					Write-Verbose -Message "Removing publish location..."
					Remove-Item -Path "$PublishLocation\$Basename" -Recurse -Confirm:$false
					If ((Test-Path -Path "$Path\$Basename"))
					{
						Write-Verbose -Message "Temporary folder already exists."
						If ((Helper-ShouldProcess -type "YesNo" -prompt "Overwrite the existing temporary module $Path\$Basename") -eq $true)
						{
							Try
							{
								Write-Verbose -Message "Removing temporary folder..."
								Remove-Item -Path "$Path\$Basename" -Recurse -Confirm:$false
								$Process = $true
							}
							Catch
							{
								Write-Error -Exception (@{ Source = "$($PSCmdlet.MyInvocation.MyCommand.Name)" }) -Message "An error occured while attempting to delete the folder `"$Path\$Basename`"."
							}
						}
						Else
						{
							Write-Host -Message "$($PSCmdlet.MyInvocation.MyCommand.Name) halted. No actions were taken."
						}
					}
					Else
					{
						$Process = $true
					}
				}
				Catch
				{
					Write-Error -Exception (@{ Source = "$($PSCmdlet.MyInvocation.MyCommand.Name)" }) -Message "An error occured while attempting to delete the folder `"$PublishLocation\$Basename`"."
				}
			}
			Else
			{
				Write-Host -Message "$($PSCmdlet.MyInvocation.MyCommand.Name) halted. No actions were taken."
			}
		}
		elseif ((Test-Path -Path "$Path\$Basename"))
		{
			Write-Verbose -Message "Temporary folder already exists."
			If ((Helper-ShouldProcess -type "YesNo" -prompt "Overwrite the existing temporary module $Path\$Basename") -eq $true)
			{
				Try
				{
					Write-Verbose -Message "Removing temporary folder..."
					Remove-Item -Path "$Path\$Basename" -Recurse -Confirm:$false
					$Process = $true
				}
				Catch
				{
					Write-Error -Exception (@{ Source = "$($PSCmdlet.MyInvocation.MyCommand.Name)" }) -Message "An error occured while attempting to delete the folder `"$Path\$Basename`"."
				}
			}
			Else
			{
				Write-Host -Message "$($PSCmdlet.MyInvocation.MyCommand.Name) halted. No actions were taken."
			}
		}
		else
		{
			$Process = $true
		}
	}
	Else
	{
		If ((Test-Path -Path "$PublishLocation\$Basename"))
		{
			Write-Output "What if: Performing the operation `"Remove-Item -Path $PublishLocation\$Basename -Force`""
			If ((Test-Path -Path "$Path\$Basename"))
			{
				Write-Output "What if: Performing the operation `"Remove-Item -Path $Path\$Basename -Force`""
			}
		}
		elseif ((Test-Path -Path "$Path\$Basename"))
		{
			Write-Output "What if: Performing the operation `"Remove-Item -Path $Path\$Basename -Force`""
		}
		$Process = $true
	}
	If ($Process -eq $true)
	{
		Write-Verbose -Message "Creating temporary folder to create manifest and PSM1 in..."
		If ($WhatIfPreference -ne $true)
		{
			Try
			{
				$ContinueProcess = $false
				New-Item -Path "$($Path)\$Basename" -ItemType directory | Out-Null
				$ContinueProcess = $true
			}
			Catch
			{
				Write-Error -Exception (@{ Source = "$($PSCmdlet.MyInvocation.MyCommand.Name)" }) -Message "An error occured while attempting to create the temporary folder."
			}
		}
		Else
		{
			Write-Output "What if: Performing the operation `"New-Item -Path `"$($Path)\$Basename`" -ItemType directory`""
			$ContinueProcess = $true
		}
		If ($ContinueProcess -eq $true)
		{
			If (($CustomProperties))
			{
				Write-Verbose -Message "Processing custom properties passed to the function..."
				foreach ($Item in $CustomProperties.GetEnumerator().Name)
				{
					Write-Verbose -Message "Processing property $Item..."
					If ($ManifestData.GetEnumerator().Name -contains $item)
					{
						Write-Verbose -Message "Manifest already contained this property. Deleting existing property value..."
						$ManifestData.Remove("$Item")
					}
					If ($ManifestPropertyTypes.GetEnumerator().Name -contains $Item)
					{
						If ($ManifestPropertyTypes."$item" -eq "array")
						{
							Write-Verbose -Message "Property is of type array."
							Write-Verbose -Message "Updating Manifest hash..."
							$ManifestData.Add("$Item", (Helper-GenerateArrayString -arrayObject $CustomProperties."$Item"))
						}
						Else
						{
							Write-Warning -Message "Unknown property type encountered."
						}
					}
					Else
					{
						Write-Verbose -Message "Property is of type string."
						Write-Verbose -Message "Updating Manifest hash..."
						$ManifestData.Add("$Item", $CustomProperties."$Item")
					}
				}
			}
			If ($CompilePS1Files -eq $true)
			{
				Write-Verbose -Message "Compiling nested scripts..."
				If (!($PSM12Export))
				{
					Write-Verbose -Message "No existing PSM1 file present. Creating new PSM1 array object."
					$PSM12Export = @()
				}
				elseif ($CompileTo -eq "Prefix")
				{
					Write-Verbose -Message "An existing PSM1 file was found, and 'CompileTo' is 'Prefix'. Saving the contents of the existing PSM1 file to append to the new file after compiling PS1 files."
					$ExistingPSM1 = $PSM12Export
					$PSM12Export = @()
				}
				else
				{
					Write-Verbose -Message "An existing PSM1 file was found, and 'CompileTo' is set to 'Append'. Any PS1 files found will be appended to the existing PSM1."
				}
				$PS1Files = Get-ChildItem -Path $Path -Filter "*.ps1"
				For ($i = 0; ($i + 1) -le $PS1Files.Count; $i++)
				{
					Write-Progress -Activity "Appending PS1 to PSM1" -Status "PS1 $i of $($PS1Files.Count)" -PercentComplete ($i / $PS1Files.count * 100)
					Write-Verbose -Message "Appending nested script $($PS1Files[$i].Name) to the new PSM1 file..."
					$PSM12Export += (Get-Content -Path $PS1Files[$i].FullName)
				}
				Write-Verbose -Message "Finished processing nested scripts."
				If ($CompileTo -eq "Prefix")
				{
					Write-Verbose -Message "Appending the contents of the original PSM1 file to the new PSM1 file."
					$PSM12Export += $ExistingPSM1
				}
				Write-Verbose -Message "Setting the RootModule in the Manifest..."
				If (($ManifestData.GetEnumerator().Name | Where-Object { $_ -eq "RootModule" }))
				{
					$ManifestData.Remove("RootModule")
				}
				Else
				{
					$ManifestData.Add("RootModule", "$($Basename).psm1")
				}
			}
			Else
			{
				Write-Verbose -Message "Adding nested scripts as Nested Modules..."
				$NestedModules = @()
				$PS1Files = Get-ChildItem -Path $Path -Filter "*.ps1"
				For ($i = 0; ($i + 1) -le $PS1Files.Count; $i++)
				{
					Write-Progress -Activity "Adding PS1 as NestedModule" -Status "PS1 $i of $($PS1Files.Count)" -PercentComplete ($i / $PS1Files.count * 100)
					Write-Verbose -Message "Appending nested script $($PS1Files[$i].Name) to NestedModules array..."
					$NestedModules += "$($PS1Files[$i].Name)"
					If ($WhatIfPreference -ne $true)
					{
						Try
						{
							Write-Verbose -Message "Copying $($PS1Files[$i].FullName) to $Path\$Basename..."
							Copy-Item -Path $PS1Files[$i].FullName -Destination "$Path\$Basename\" -Force	
						}
						Catch
						{
							Write-Error -Exception (@{ Source = "$($PSCmdlet.MyInvocation.MyCommand.Name)" }) -Message "An error occured while attempting to copy $($PS1Files[$i].Name) to $Path\$Basename."
						}
					}
					Else
					{
						Write-Output "What if: Performing the operation `"Copy-Item -Path $($PS1Files[$i].FullName) -Destination $Path\$Basename`""
					}
				}
				Write-Verbose -Message "Updating Manifest hash with new NestedModules property value..."
				$ManifestData.Remove("NestedModules")
				$ManifestData.Add("NestedModules", $NestedModules)
			}
			Write-Verbose -Message "Setting Manifest path..."
			$ManifestData.Add("Path", "$Path\$Basename\$Basename.psd1")
			If (($ManifestData.GetEnumerator().Name | Where-Object { $_ -eq "PrivateData" }))
			{
				$ManifestData.Remove("PrivateData")
			}
			Write-Verbose -Message "Saving manifest..."
			Try
			{
				If ($WhatIfPreference -ne $true)
				{
					New-ModuleManifest @ManifestData | Out-Null
				}
				Else
				{
					Write-Output "What if: Performing the operation `"New-ModuleManifest`" against the path $Path\$Basename\$Basename.psd1."
				}
			}
			Catch
			{
				Write-Error -Exception (@{ Source = "$($PSCmdlet.MyInvocation.MyCommand.Name)" }) -Message "An error occured while attempting to save the Manifest data."
			}
			If (($PSM12Export))
			{
				Write-Verbose -Message "Saving PSM1..."
				Try
				{
					If ($WhatIfPreference -ne $true)
					{
						Set-Content -Path "$Path\$Basename\$Basename.psm1" -Value $PSM12Export | Out-Null
					}
					Else
					{
						Write-Output "What if: Performing the operation `"Set-Content -Path `"$Path\$Basename\$Basename.psm1`" -Value `$PSM12Export`""
					}
				}
				Catch
				{
					Write-Error -Exception (@{ Source = "$($PSCmdlet.MyInvocation.MyCommand.Name)" }) -Message "An error occured while attempting to save the PSM1 data."
				}
			}
			If ($DigitallySign -eq $true)
			{
				Write-Verbose -Message "Attempting to digitally sign files..."
				Helper-Set-AuthenticodeSignature -FilePath "$Path\$Basename\$Basename.psd1" -Certificate $Certificate
				If ($WhatIfPreference -ne $true)
				{
					If ((Test-Path -Path "$Path\$Basename\$Basename.psm1"))
					{
						Helper-Set-AuthenticodeSignature -FilePath "$Path\$Basename\$Basename.psm1" -Certificate $Certificate
					}	
				}
				Else
				{
					If (($PSM12Export))
					{
						Helper-Set-AuthenticodeSignature -FilePath "$Path\$Basename\$Basename.psm1" -Certificate $Certificate
					}		
				}
				If ($WhatIfPreference -ne $true)
				{
					If (($CompilePS1Files -eq $false) -and ((Get-ChildItem -Path "$Path\$Basename" -Filter "*.ps1").Count -ge 1))
					{
						foreach ($ps1 in (Get-ChildItem -Path "$Path\$Basename" -Filter "*.ps1"))
						{
							Helper-Set-AuthenticodeSignature -FilePath "$($ps1.FullName)" -Certificate $Certificate
						}
					}	
				}
				Else
				{
					If (($CompilePS1Files -eq $false) -and ((Get-ChildItem -Path "$Path" -Filter "*.ps1").Count -ge 1))
					{
						foreach ($ps1 in (Get-ChildItem -Path "$Path" -Filter "*.ps1"))
						{
							Helper-Set-AuthenticodeSignature -FilePath "$($ps1.FullName)" -Certificate $Certificate
						}
					}
				}
			}
			If (($PublishLocation))
			{
				Write-Verbose -Message "Copying files from temporary location to publish location..."
				If (($WhatIfPreference -ne $true) -and (($PublishLocation)))
				{
					Try
					{
						$timer = New-Object System.Timers.Timer
						$timer.Interval = 500
						$global:SourceCount = (Get-ChildItem -Path "$Path\$Basename" -Recurse).count
						$global:CopyStatus = $false
						$global:CopyToLocation = "$PublishLocation\$Basename"
						$action = {
							$PublishCount = (Get-ChildItem -Path "$CopyToLocation" -Recurse).count
							Write-Progress -Activity "Copying files" -Status "$PublishCount of $SourceCount" -PercentComplete ($PublishCount / $SourceCount * 100)
							If ($PublishCount -eq $SourceCount)
							{
								$global:CopyStatus = $true
							}
						}
						$start = Register-ObjectEvent -InputObject $timer -SourceIdentifier TimerElapsed -EventName Elapsed -Action $action
						Start-Job -Name "CopyToPublish" -ScriptBlock {
							param (
								$Source,
								$Destination
							)
							Try
							{
								Copy-Item -Path "$Source" -Destination "$Destination" -Recurse -Force
								return, $true
							}
							Catch
							{
								return, $Error	
							}
						} -ArgumentList "$Path\$Basename", "$PublishLocation\$Basename" | Out-Null
						Write-Verbose -Message "Waiting for the Manifest Module to get copied to the publish location..."
						$timer.Start()
						$execute = $true
						while ($execute -eq $true)
						{
							Start-Sleep -Second 1
							if ($global:CopyStatus -eq $true)
							{
								$execute = $false
							}
						}
						$timer.Stop()
						Unregister-Event TimerElapsed
						$CopytoPublishResults = Receive-Job -Name 'CopyToPublish'
						If ($CopytoPublishResults -ne $true)
						{
							Write-Error -Exception (@{ Source = "$($PSCmdlet.MyInvocation.MyCommand.Name)" }) -Message "An error occured while attempting to copy the files to the publish location.`n`n$CopytoPublishResults"	
						}
					}
					catch
					{
						Write-Error -Exception (@{ Source = "$($PSCmdlet.MyInvocation.MyCommand.Name)" }) -Message "An error occured while attempting to copy the files to the publish location."
					}
				}
				elseif (($PublishLocation))
				{
					
					Write-Output "What if: Performing the operation `"Copy-Item -Path $Path\$Basename -Destination $PublishLocation\$Basename -Recurse -Force`""
				}
			}
			If ($WhatIfPreference -ne $true)
			{
				Write-Output -InputObject "$($PSCmdlet.MyInvocation.MyCommand.Name) successful."
				Write-Output -InputObject ""
			}
			Else
			{
				Write-Output -InputObject "$($PSCmdlet.MyInvocation.MyCommand.Name) operations complete."
				Write-Output -InputObject ""
			}
		}	
	}
}